# Copyright (c) 2009-2011 VMware, Inc.
require 'set'
require 'uuidtools'

module VCAP
  module Services
    module MSSB
      class Node < VCAP::Services::Base::Node
      end
    end
  end
end

require "mssb_service/common"
require "mssb_service/mssb_error"

VALID_CREDENTIAL_CHARACTERS = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a

class VCAP::Services::MSSB::Node

  include VCAP::Services::MSSB::Common
  include VCAP::Services::MSSB

  class Provisionedservice
    include DataMapper::Resource
    property :name,        String,  :key => true # UUID
    property :group,       String,  :required => true
    # property plan is deprecated
    property :plan,        Integer, :required => true
    property :plan_option, String,  :required => false
    property :memory,      Integer, :required => true
    property :status,      Integer, :default => 0
    has n, :bindusers

    # Must build command this way to ensure executing 64-bit powershell
    def powershell_exe
      @powershell_exe ||= File.join(ENV['WINDIR'], 'sysnative', 'WindowsPowerShell', 'v1.0', 'powershell.exe').gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    end

    def create(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Create -Name #{name} -ManageUser #{group}"
      exe_cmd(logger, cmd)
    end

    def running?(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Check -Name #{name}"
      return exe_cmd(logger, cmd)
    end

    def delete(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Delete -Name #{name}"
      exe_cmd(logger, cmd)
    end

    def disable(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Manage -Name #{name} -ManageUser Guests"
      exe_cmd(logger, cmd)
    end

    def enable(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Manage -Name #{name} -ManageUser #{group}"
      exe_cmd(logger, cmd)
    end

    private
    def exe_cmd(logger, cmd)
      logger.debug("Execute shell cmd: [#{cmd}]")
      o = %x(#{cmd})
      s = $?
      if s.success?
        logger.debug("Execute cmd success.")
      else
        logger.error("Execute cmd failed. output: [#{o}]")
      end
      return s.success?
    end
  end

  class Binduser
    include DataMapper::Resource
    property :user, String, :key => true
    belongs_to :provisionedservice
  end

  def initialize(options)
    super(options)
    @hostname = get_host
    # DataMapper::Logger.new($stdout, :debug)
    DataMapper.setup(:default, options[:local_db])
    DataMapper::auto_upgrade!
  end

  def pre_send_announcement
    super
    start_provisioned_instances
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity, :capacity_unit => capacity_unit }
    end
  end

  def add_local_group(groupname)
    net_cmd = "net localgroup #{groupname} /add"
    unless exe_cmd(net_cmd)
      raise MSSBError.new(MSSBError::MSSB_ADD_GROUP_FAILED, groupname)
    end
  end

  def delete_local_group(groupname, users = [])
    users.each do |user|
      delete_local_user(user)
    end
    net_cmd = "net localgroup #{groupname} /delete"
    exe_cmd(net_cmd)
  end

  def add_local_user(groupname, username, password)
    @logger.debug("add_local_user(#{groupname}, #{username}, #{password})")
    net_user_cmd = "net user #{username} #{password} /add /expires:never"
    unless exe_cmd(net_user_cmd)
      raise MSSBError.new(MSSBError::MSSB_ADD_USER_FAILED, username)
    end
    wmic_cmd = "wmic path Win32_UserAccount where Name='#{username}' set PasswordExpires=false"
    unless exe_cmd(wmic_cmd)
      raise MSSBError.new(MSSBError::MSSB_MODIFY_USER_FAILED, username)
    end
    net_grp_cmd = "net localgroup #{groupname} #{username} /add"
    unless exe_cmd(net_grp_cmd)
      raise MSSBError.new(MSSBError::MSSB_ADD_GROUP_FAILED, groupname)
    end
  end

  def delete_local_user(username)
    exe_cmd("net user #{username} /delete")
  end

  def provision(plan, credentials=nil, version=nil)
    raise MSSBError.new(MSSBError::MSSB_INVALID_PLAN, plan) unless plan.to_s == @plan

    instance = Provisionedservice.new
    instance.plan = 1
    instance.plan_option = ''
    instance.memory = 1

    if credentials
      instance.name  = credentials["name"]
      instance.group = credentials["group"]
    else
      instance.name  = 'ns' + UUIDTools::UUID.random_create.to_s.delete('-')
      instance.group = 'grp' + generate_credential
      credentials = Hash.new
    end

    user = 'u' + generate_credential
    pass = 'p' + generate_credential
    credentials['username'] = user
    credentials['password'] = pass

    binduser = Binduser.new
    binduser.user = user

    begin
      add_local_group(instance.group)
      add_local_user(instance.group, user, pass)
      create_instance(instance)
      save_instance(instance, binduser)
    rescue => e1
      begin
        cleanup_instance(instance)
      rescue => e2
        # Ignore the rollback exception
      end
      raise e1
    end

    gen_credentials(instance, user, pass)
  end

  def unprovision(instance_id, credentials_list = [])
    instance = get_instance(instance_id)
    cleanup_instance(instance)
    {}
  end

  def bind(instance_id, binding_options = :all, binding_credentials = nil)
    instance = get_instance(instance_id)
    user = nil
    pass = nil
    if binding_credentials
      # assuming local user exists
      user = binding_credentials["user"]
      pass = binding_credentials["pass"]
    else
      user = "u" + generate_credential
      pass = "p" + generate_credential
      add_local_user(instance.group, user, pass)
      binduser = Binduser.new
      binduser.user = user
      save_instance(instance, binduser)
    end
    gen_credentials(instance, user, pass)
  rescue => e
    # Rollback
    begin
      delete_local_user(user)
    rescue => e1
      # Ignore the exception here
    end
    raise e
  end

  def unbind(credentials)
    instance_name = credentials['name']
    user = credentials['user']
    instance = get_instance(instance_name)
    unbinduser = provisionedservice.bindusers.get(user)
    delete_local_user(unbinduser)
    unless unbinduser.destroy
      @logger.error("Could not delete user: #{unbinduser.errors.inspect}")
    end
    {}
  end

  def varz_details
    varz = {}
    varz[:provisioned_instances] = []
    varz[:provisioned_instances_num] = 0
    varz[:max_capacity] = @max_capacity
    varz[:available_capacity] = @capacity
    varz[:instances] = {}
    Provisionedservice.all.each do |instance|
      varz[:instances][instance.name.to_sym] = get_status(instance)
    end
    Provisionedservice.all.each do |instance|
      varz[:provisioned_instances_num] += 1
      begin
        varz[:provisioned_instances] << get_varz(instance)
      rescue => e
        @logger.warn("Failed to get instance #{instance.name} varz details: #{e}")
      end
    end
    varz
  rescue => e
    @logger.warn(e)
    {}
  end

  def disable_instance(service_credentials, binding_credentials_list = [])
    @logger.info("disable_instance request: service_credentials=#{service_credentials}, binding_credentials=#{binding_credentials_list}")
    instance = get_instance(service_credentials["name"])
    instance.disable(@logger)
    true
  rescue => e
    @logger.warn(e)
    nil
  end

  def enable_instance(service_credentials, binding_credentials_map={})
    instance = get_instance(service_credentials["name"])
    instance.enable(@logger)
    service_credentials["hostname"] = @hostname
    service_credentials["host"] = @hostname
    binding_credentials_map.each do |key, value|
      bind(service_credentials["name"], value["binding_options"], value["credentials"])
      binding_credentials_map[key]["credentials"]["hostname"] = @hostname
      binding_credentials_map[key]["credentials"]["host"] = @hostname
    end
    [service_credentials, binding_credentials_map]
  rescue => e
    @logger.warn(e)
    nil
  end

  def dump_instance(service_credentials, binding_credentials_list, dump_dir)
    true
  end

  def import_instance(service_credentials, binding_credentials_map, dump_dir, plan)
    provision(plan, service_credentials)
  end

  def all_instances_list
    Provisionedservice.all.map{|s| s.name}
  end

  def all_bindings_list
    res = []
    Provisionedservice.all.each do |instance|
        credentials = {
          "name" => instance.name,
          "group" => instance.group,
          "hostname" => @hostname,
          "host" => @hostname,
        }
        res << credentials
      end
    res
  end

  def start_provisioned_instances
    @capacity_lock.synchronize do
      Provisionedservice.all.each do |instance|
        @capacity -= capacity_unit
        if instance.running?(@logger)
          @logger.warn("Service #{instance.name} already running.")
          next
        end
        begin
          create_instance(instance)
        rescue => e
          @logger.warn("Error starting instance #{instance.name}: #{e}")
        end
      end
    end
  end

  def save_instance(instance, binduser)
    instance.bindusers << binduser
    if not binduser.save
      raise MSSBError.new(MSSBError::MSSB_SAVE_USER_FAILED, binduser.inspect)
    end
    if not instance.save
      raise MSSBError.new(MSSBError::MSSB_SAVE_INSTANCE_FAILED, instance.inspect)
    end
    true
  end

  def destroy_instance(instance)
    instance.bindusers.all.each do |binduser|
      unless binduser.destroy
        @logger.error("Could not delete binduser: #{binduser.errors.inspect}")
      end
    end
    unless instance.destroy!
      @logger.error("Could not delete instance: #{instance.errors.inspect}")
    end
    @logger.info("Successfully fulfilled unprovision request: #{instance.name}")
    true
  end

  def get_instance(instance_name)
    instance = Provisionedservice.get(instance_name)
    raise MSSBError.new(MSSBError::MSSB_FIND_INSTANCE_FAILED, instance_name) if instance.nil?
    instance
  end

  def create_instance(instance)
    @logger.debug("Creating: #{instance.inspect} with namespace #{instance.name}")
    instance.create(@logger)
  end

  def cleanup_instance(instance)
    err_msg = []
    begin
      instance.delete(@logger)
      users = instance.bindusers.map { |u| u.user }
      delete_local_group(instance.group, users)
    rescue => e
      err_msg << e.message
    end
    begin
      destroy_instance(instance)
    rescue => e
      err_msg << e.message
    end
    raise MSSBError.new(MSSBError::MSSB_CLEANUP_INSTANCE_FAILED, err_msg.inspect) if err_msg.size > 0
  end

  def generate_credential(length = 12)
    Array.new(length) {VALID_CREDENTIAL_CHARACTERS[rand(VALID_CREDENTIAL_CHARACTERS.length)]}.join
  end

  def get_varz(instance)
    varz = {}
    varz[:name] = instance.name
    varz[:plan] = @plan
    varz[:group] = instance.group
    varz[:usage] = {} # TODO
    varz
  end

  def get_status(instance)
    instance.running?(@logger) ? "ok" : "fail"
  rescue => e
    "fail"
  end

  def gen_credentials(instance, user, pass)
    credentials = {
      "name" => instance.name,
      "hostname" => @hostname,
      "host" => @hostname,
      "username" => user,
      "password" => pass,
    }
    credentials["sb_oauth_https"] = "https://#{@hostname}:4446/#{instance.name}/$STS/OAuth/"
    credentials["sb_oauth"] = "sb://#{@hostname}:4446/#{instance.name}/"
    credentials["sb_runtime_address"] = "sb://#{@hostname}:9354/#{instance.name}/"
    credentials
  end

  private
  def exe_cmd(cmd)
    @logger.debug("Execute shell cmd: [#{cmd}]")
    o = %x(#{cmd})
    s = $?
    if s.success?
      @logger.debug("Execute cmd success.")
    else
      @logger.error("Execute cmd failed. output: [#{o}]")
    end
    s.success?
  end
end
