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
require "mssb_service/util"

VALID_CREDENTIAL_CHARACTERS = ("A".."Z").to_a + ("a".."z").to_a + ("0".."9").to_a

class VCAP::Services::MSSB::Node

  include VCAP::Services::MSSB::Common
  include VCAP::Services::MSSB::Util
  include VCAP::Services::MSSB

  class ProvisionedService
    include DataMapper::Resource
    property :name,        String,  :key => true # UUID
    property :username,    String,  :required => true
    property :password,    String,  :required => true
    # property plan is deprecated
    property :plan,        Integer, :required => true
    property :plan_option, String,  :required => false
    property :memory,      Integer, :required => true
    property :status,      Integer, :default => 0

    # TODO must build command this way to ensure executing 64-bit powershell
    def powershell_exe
      @powershell_exe ||= File.join(ENV['WINDIR'], 'sysnative', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    end

    def start(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Create -Name #{name}"
      exe_cmd(logger, cmd)
    end

    def running?(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Check -Name #{name}"
      o, e, s = exe_cmd(logger, cmd)
      return s.successful?
    end

    def stop(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Delete -Name #{name}"
      exe_cmd(logger, cmd)
    end

    private
    def exe_cmd(logger, cmd)
      logger.debug("Execute shell cmd: [#{cmd}]")
      o, e, s = Open3.capture3(cmd)
      if s.successful?
        logger.debug("Execute cmd: [#{cmd}] success.")
      else
        logger.error("Execute cmd: [#{cmd}] failed. stdout: [#{o}], stderr: [#{e}]")
      end
    end
  end

  def initialize(options)
    super(options)

    @local_db = options[:local_db]

    @base_dir = options[:base_dir]
    FileUtils.mkdir_p(@base_dir) if @base_dir

    @hostname = get_host
    @supported_versions = ["1.0"]
  end

  def pre_send_announcement
    super
    start_db
    start_provisioned_instances
  end

  def shutdown
    super
    ProvisionedService.all.each { |instance|
      @logger.debug("Try to stop MSSB namespace: #{instance.name}")
      instance.stop(@logger)
    }
    true
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity, :capacity_unit => capacity_unit }
    end
  end

  def add_local_user(username, password)
    net_cmd = "net user #{username} #{password} /add /expires:never"
    exe_cmd(net_cmd)
    wmic_cmd = "wmic path Win32_UserAccount where Name='#{username}' set PasswordExpires=false"
    exe_cmd(wmic_cmd)
  end

  def delete_local_user(username)
    exe_cmd("net user #{username} /delete")
  end

  def provision(plan, credentials = nil, version=nil)
    raise MSSBError.new(MSSBError::MSSB_INVALID_PLAN, plan) unless plan.to_s == @plan
    instance = ProvisionedService.new
    instance.plan = 1
    instance.plan_option = ''
    if credentials
      instance.name      = credentials["name"]
      instance.username  = credentials["username"]
      instance.password  = credentials["password"]
    else
      instance.name     = UUIDTools::UUID.random_create.to_s
      instance.username = "u" + generate_credential
      instance.password = "p" + generate_credential
    end
    begin
      credentials['username'] = instance.username
      credentials['password'] = instance.password
      add_local_user(instance.username, instance.password)
      start_instance(instance)
      save_instance(instance)
    rescue => e1
      begin
        cleanup_instance(instance)
      rescue => e2
        # Ignore the rollback exception
      end
      raise e1
    end

    gen_credentials(instance)
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
      user = binding_credentials["user"]
      pass = binding_credentials["pass"]
    else
      user = "u" + generate_credential
      pass = "p" + generate_credential
    end
    # credentials = gen_admin_credentials(instance)
    add_local_user(user, pass)
    # TODO use Set-SBNamespace to add user?
    set_permissions(credentials, instance.vhost, user, get_permissions_by_options(binding_options))
    gen_credentials(instance, user, pass)
  rescue => e
    # Rollback
    begin
      delete_user(user)
    rescue => e1
      # Ignore the exception here
    end
    raise e
  end

  def unbind(credentials)
    instance = get_instance(credentials["name"])
    delete_user(gen_admin_credentials(instance), credentials["user"])
    {}
  end

  def varz_details
    varz = {}
    varz[:provisioned_instances] = []
    varz[:provisioned_instances_num] = 0
    varz[:max_capacity] = @max_capacity
    varz[:available_capacity] = @capacity
    varz[:instances] = {}
    ProvisionedService.all.each do |instance|
      varz[:instances][instance.name.to_sym] = get_status(instance)
    end
    ProvisionedService.all.each do |instance|
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
    # TODO how to disable MSSB?
    true
  rescue => e
    @logger.warn(e)
    nil
  end

  def enable_instance(service_credentials, binding_credentials_map={})
    instance = get_instance(service_credentials["name"])
    # TODO hmmm get_permissions(gen_admin_credentials(instance), service_credentials["vhost"], service_credentials["user"])
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

  # MSSBmq has no data to dump for migration
  def dump_instance(service_credentials, binding_credentials_list, dump_dir)
    true
  end

  def import_instance(service_credentials, binding_credentials_map, dump_dir, plan)
    provision(plan, service_credentials)
  end

  def all_instances_list
    ProvisionedService.all.map{|s| s.name}
  end

  def all_bindings_list
    res = []
    ProvisionedService.all.each do |instance|
        credentials = {
          "name" => instance.name,
          "hostname" => @hostname,
          "host" => @hostname,
          "username" => instance.username,
          "user" => instance.username,
        }
        res << credentials
      end
    end
    res
  end

  def start_db
    DataMapper.setup(:default, @local_db)
    DataMapper::auto_upgrade!
  end

  def start_provisioned_instances
    @capacity_lock.synchronize do
      ProvisionedService.all.each do |instance|
        @capacity -= capacity_unit
        if instance.running?(@logger)
          @logger.warn("Service #{instance.name} already running on port #{instance.port}")
          next
        end
        begin
          start_instance(instance)
          save_instance(instance)
        rescue => e
          @logger.warn("Error starting instance #{instance.name}: #{e}")
        end
      end
    end
  end

  def save_instance(instance)
    raise MSSBError.new(MSSBError::MSSB_SAVE_INSTANCE_FAILED, instance.inspect) unless instance.save
    true
  end

  def destroy_instance(instance)
    # Here need check whether the object is in db or not,
    # otherwise the destory operation will persist the object from memory to db without deleting it,
    # the behavior of datamapper is doing persistent work at the end of each save/update/destroy API
    raise MSSBError.new(MSSBError::MSSB_DESTORY_INSTANCE_FAILED, instance.inspect) unless instance.new? || instance.destroy
    true
  end

  def get_instance(instance_name)
    instance = ProvisionedService.get(instance_name)
    raise MSSBError.new(MSSBError::MSSB_FIND_INSTANCE_FAILED, instance_name) if instance.nil?
    instance
  end

  def start_instance(instance)
    @logger.debug("Starting: #{instance.inspect} with namespace #{instance.name}")
    instance.start(@logger)
  end

  def stop_instance(instance)
    instance.stop(@logger)
  end

  def cleanup_instance(instance)
    err_msg = []
    begin
      stop_instance(instance) if instance.running?
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
    varz[:username] = instance.username
    varz[:usage] = {}
    credentials = gen_admin_credentials(instance)
    varz[:usage][:queues_num] = list_queues(credentials, instance.vhost).size
    varz[:usage][:exchanges_num] = list_exchanges(credentials, instance.vhost).size
    varz[:usage][:bindings_num] = list_bindings(credentials, instance.vhost).size
    varz
  end

  def get_status(instance)
    instance.running? ? "ok" : "fail"
  rescue => e
    "fail"
  end

  def gen_credentials(instance, user = nil, pass = nil)
    credentials = {
      "name" => instance.name,
      "hostname" => @hostname,
      "host" => @hostname,
    }
    if user && pass # Binding request
      credentials["username"] = user
      credentials["password"] = pass
    else # Provision request
      credentials["username"] = instance.username
      credentials["password"] = instance.admin_password
    end
    credentials["oauth"] = "https://@hostname:4446/#{instance.name}/$STS/OAuth/"
    credentials
  end

  private
  def exe_cmd(cmd)
    @logger.debug("Execute shell cmd: [#{cmd}]")
    o, e, s = Open3.capture3(cmd)
    if s.successful?
      @logger.debug("Execute cmd: [#{cmd}] success.")
    else
      @logger.error("Execute cmd: [#{cmd}] failed. stdout: [#{o}], stderr: [#{e}]")
    end
  end
end
