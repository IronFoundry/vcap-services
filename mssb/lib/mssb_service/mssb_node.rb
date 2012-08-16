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
    property :namespace,      String,  :key => true
    property :admin_username, String,  :required => true
    property :admin_password, String,  :required => true
    # property plan is deprecaed. The inces in one node have same plan.
    property :plan,           Integer, :required => true
    property :plan_option,    String,  :required => false
    property :memory,         Integer, :required => true
    property :status,         Integer, :default => 0

    # TODO must build command this way to ensure executing 64-bit powershell
    def powershell_exe
      @powershell_exe ||= File.join(ENV['WINDIR'], 'sysnative', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    end

    def listening?
      # TODO - rewrite for MSSB
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Check -Name #{namespace}"
      o, e, s = exe_cmd(logger, cmd)
      return s.successful?
    end

    def running?
      # TODO - rewrite for MSSB
      # Should use Get-SBNamespace to verify
      true
    end

    def remove_namespace(logger)
      cmd =  powershell_exe + " -ExecutionPolicy ByPass -NoLogo -NonInteractive -File managesb.ps1 -Delete -Name #{namespace}"
      exe_cmd(logger, cmd)
    end

    private
    def exe_cmd(logger, cmd)
      @logger.debug("Execute shell cmd: [#{cmd}]")
      o, e, s = Open3.capture3(cmd)
      if s.successful?
        @logger.debug("Execute cmd: [#{cmd}] success.")
      else
        @logger.error("Execute cmd: [#{cmd}] failed. stdout: [#{o}], stderr: [#{e}]")
      end
    end
  end

  def initialize(options)
    super(options)

    @config_template = ERB.new(File.read(options[:config_template]))

    # @free_ports = Set.new
    # @free_admin_ports = Set.new
    # @free_ports_mutex = Mutex.new
    # options[:port_range].each {|port| @free_ports << port}
    # options[:admin_port_range].each {|port| @free_admin_ports << port}
    # @port_gap = options[:admin_port_range].first - options[:port_range].first

    @max_memory_factor = options[:max_memory_factor] || 0.5
    @local_db = options[:local_db]
    # TODO @binding_options = nil
    @base_dir = options[:base_dir]

    FileUtils.mkdir_p(@base_dir) if @base_dir
    # TODO @mssb_server = @options[:mssb_server]
    @mssb_log_dir = @options[:mssb_log_dir]
    @max_clients = @options[:max_clients] || 500

    # Timeout for mssb client operations, node cannot be blocked on any mssb instances.
    # Default value is 2 seconds.
    @mssb_timeout = @options[:mssb_timeout] || 2
    @mssb_start_timeout = @options[:mssb_start_timeout] || 5

    # @default_permissions = '{"configure":".*","write":".*","read":".*"}'
    @initial_username = "guest"
    @initial_password = "guest"

    @hostname = get_host
    @supported_versions = ["1.0"]
  end

  def pre_send_announcement
    super
    start_db
    start_provisioned_instances
  end

  def shutdown
    # TODO: remove all namespaces
    super
    ProvisionedService.all.each { |instance|
      @logger.debug("Try to remove MSSB namespace: #{instance.pid}")
      instance.remove_namespace(@logger)
    }
    true
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity, :capacity_unit => capacity_unit }
    end
  end

  def provision(plan, credentials = nil, version=nil)
    raise MSSBError.new(MSSBError::MSSB_INVALID_PLAN, plan) unless plan.to_s == @plan
    instance = ProvisionedService.new
    instance.plan = 1
    instance.plan_option = ""
    if credentials
      instance.name = credentials["name"]
      instance.vhost = credentials["vhost"]
      instance.admin_username = credentials["user"]
      instance.admin_password = credentials["pass"]
      @free_ports_mutex.synchronize do
        if @free_ports.include?(credentials["port"])
          @free_ports.delete(credentials["port"])
          @free_admin_ports.delete(credentials["port"] + @port_gap)
          instance.port = credentials["port"]
          instance.admin_port = credentials["port"] + @port_gap
        else
          port = @free_ports.first
          @free_ports.delete(port)
          @free_admin_ports.delete(port + @port_gap)
          instance.port = port
          instance.admin_port = port + @port_gap
        end
      end
    else
      instance.name = UUIDTools::UUID.random_create.to_s
      instance.vhost = "v" + UUIDTools::UUID.random_create.to_s.gsub(/-/, "")
      instance.admin_username = "au" + generate_credential
      instance.admin_password = "ap" + generate_credential
      port = @free_ports.first
      @free_ports.delete(port)
      @free_admin_ports.delete(port + @port_gap)
      instance.port = port
      instance.admin_port = port + @port_gap
    end
    begin
      instance.memory = memory_for_instance(instance)
    rescue => e
      raise e
    end
    begin
      instance.pid = start_instance(instance)
      save_instance(instance)
      # Use initial credentials to create provision user
      credentials = {"username" => @initial_username, "password" => @initial_password, "admin_port" => instance.admin_port}
      add_vhost(credentials, instance.vhost)
      add_user(credentials, instance.admin_username, instance.admin_password)
      set_permissions(credentials, instance.vhost, instance.admin_username, @default_permissions)
      # Use provision user credentials to delete initial user for security
      credentials["username"] = instance.admin_username
      credentials["password"] = instance.admin_password
      delete_user(credentials, @initial_username)
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
    credentials = gen_admin_credentials(instance)
    add_user(credentials, user, pass)
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
    # Delete all binding users
    binding_credentials_list.each do |credentials|
      delete_user(gen_admin_credentials(instance), credentials["user"])
    end
    true
  rescue => e
    @logger.warn(e)
    nil
  end

  def enable_instance(service_credentials, binding_credentials_map={})
    instance = get_instance(service_credentials["name"])
    get_permissions(gen_admin_credentials(instance), service_credentials["vhost"], service_credentials["user"])
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
      get_vhost_permissions(gen_admin_credentials(instance), instance.vhost).each do |entry|
        credentials = {
          "name" => instance.name,
          "hostname" => @hostname,
          "host" => @hostname,
          "port" => instance.port,
          "vhost" => instance.vhost,
          "username" => entry["user"],
          "user" => entry["user"],
        }
        res << credentials if credentials["username"] != instance.admin_username
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
        if instance.listening?(@local_ip)
          @logger.warn("Service #{instance.name} already running on port #{instance.port}")
          next
        end
        begin
          instance.pid = start_instance(instance)
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

  def get_instance(instance_id)
    instance = ProvisionedService.get(instance_id)
    raise MSSBError.new(MSSBError::MSSB_FIND_INSTANCE_FAILED, instance_id) if instance.nil?
    instance
  end

  def memory_for_instance(instance)
    #FIXME: actually this field has no effect on instance, the memory usage is decided by max_capacity
    1
  end

  def start_instance(instance)
    @logger.debug("Starting: #{instance.inspect} on port #{instance.port}")

    pid = Process.fork do
      $0 = "Starting MSSBMQ instance: #{instance.name}"
      close_fds

      dir = instance_dir(instance.name)
      config_dir = File.join(dir, "config")
      log_dir = instance_log_dir(instance.name)
      FileUtils.mkdir_p(config_dir)
      FileUtils.mkdir_p(log_dir)
      admin_port = instance.admin_port
      # To allow for garbage-collection, http://www.mssb.com/memory.html recommends that vm_memory_high_watermark be set to 40%.
      # But since we run up to @max_capacity instances on each node, we must give each instance less than 40% of the memory.
      # Analysis of the worst case (all instances are very busy and doing GC at the same time) suggests that we should set vm_memory_high_watermark = 0.4 / @max_capacity.
      # But we do not expect to ever see this worst-case situation in practice, so we
      # (a) allow a numerator different from 40%, @max_memory_factor defaults to 50%;
      # (b) make the number grow more slowly as of @max_capacity increases.
      vm_memory_high_watermark = @max_memory_factor / (1 + Math.log(@max_capacity))
      # In MSSBMQ, If the file_handles_high_watermark is x, then the socket limitation is x * 0.9 - 2,
      # to let the @max_clients be a more accurate limitation, the file_handles_high_watermark will be set to
      # (@max_clients + 2) / 0.9
      file_handles_high_watermark = ((@max_clients + 2) / 0.9).to_i
      # Writes the MSSBMQ server erlang configuration file
      config = @config_template.result(Kernel.binding)
      File.open(File.join(config_dir, "mssb.config"), "w") {|f| f.write(config)}
      # Enable management plugin
      File.open(File.join(config_dir, "enabled_plugins"), "w") do |f|
        f.write <<EOF
[mssb_management].
EOF
      end
      # Set up the environment
      {
        "HOME" => dir,
        "MSSBMQ_NODENAME" => "#{instance.name}@localhost",
        "MSSBMQ_NODE_IP_ADDRESS" => @local_ip,
        "MSSBMQ_NODE_PORT" => instance.port.to_s,
        "MSSBMQ_BASE" => dir,
        "MSSBMQ_LOG_BASE" => log_dir,
        "MSSBMQ_MNESIA_DIR" => File.join(dir, "mnesia"),
        "MSSBMQ_PLUGINS_EXPAND_DIR" => File.join(dir, "plugins"),
        "MSSBMQ_CONFIG_FILE" => File.join(config_dir, "mssb"),
        "MSSBMQ_ENABLED_PLUGINS_FILE" => File.join(config_dir, "enabled_plugins"),
        "MSSBMQ_SERVER_START_ARGS" => "-smp disable",
        "MSSBMQ_CONSOLE_LOG" => "reuse",
        "ERL_CRASH_DUMP" => "/dev/null",
        "ERL_CRASH_DUMP_SECONDS" => "1",
      }.each_pair { |k, v|
        ENV[k] = v
      }

      STDOUT.reopen(File.open("#{log_dir}/mssb_stdout.log", "w"))
      STDERR.reopen(File.open("#{log_dir}/mssb_stderr.log", "w"))
      exec("#{@mssb_server}")
    end
    # In parent, detch the child.
    Process.detach(pid)
    @logger.debug("Service #{instance.name} started with pid #{pid}")
    # Wait enough time for the MSSBMQ server starting
    (1..@mssb_start_timeout).each do
      sleep 1
      if instance.pid # An existed instance
        credentials = {"username" => instance.admin_username, "password" => instance.admin_password, "admin_port" => instance.admin_port}
      else # A new instance
        credentials = {"username" => @initial_username, "password" => @initial_password, "admin_port" => instance.admin_port}
      end
      begin
        # Try to call management API, if success, then return
        response = create_resource(credentials)["users"].get
        JSON.parse(response)
        return pid
      rescue => e
        next
      end
    end
    @logger.error("Timeout to start MSSBMQ server for instance #{instance.name}")
    if instance.pid
      # For existed instance, just return the pid, the instance will finish starting eventually
      # and varz will report its status
      return pid
    else
      # For new instance, stop the instance if it is running
      instance.pid = pid
      stop_instance(instance) if instance.running?
      raise MSSBError.new(MSSBError::MSSB_START_INSTANCE_FAILED, instance.inspect)
    end
  end

  def stop_instance(instance)
    instance.kill
    EM.defer do
      FileUtils.rm_rf(instance_dir(instance.name))
      FileUtils.rm_rf(instance_log_dir(instance.name))
    end
  end

  def cleanup_instance(instance)
    err_msg = []
    begin
      stop_instance(instance) if instance.running?
    rescue => e
      err_msg << e.message
    end
    @free_ports_mutex.synchronize do
      @free_ports.add(instance.port)
      @free_admin_ports.add(instance.admin_port)
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
    varz[:vhost] = instance.vhost
    varz[:admin_username] = instance.admin_username
    varz[:usage] = {}
    credentials = gen_admin_credentials(instance)
    varz[:usage][:queues_num] = list_queues(credentials, instance.vhost).size
    varz[:usage][:exchanges_num] = list_exchanges(credentials, instance.vhost).size
    varz[:usage][:bindings_num] = list_bindings(credentials, instance.vhost).size
    varz
  end

  def get_status(instance)
    get_permissions(gen_admin_credentials(instance), instance.vhost, instance.admin_username) ? "ok" : "fail"
  rescue => e
    "fail"
  end

  def gen_credentials(instance, user = nil, pass = nil)
    credentials = {
      "name" => instance.name,
      "hostname" => @hostname,
      "host" => @hostname,
      "port"  => instance.port,
      "vhost" => instance.vhost,
    }
    if user && pass # Binding request
      credentials["username"] = user
      credentials["user"] = user
      credentials["password"] = pass
      credentials["pass"] = pass
    else # Provision request
      credentials["username"] = instance.admin_username
      credentials["user"] = instance.admin_username
      credentials["password"] = instance.admin_password
      credentials["pass"] = instance.admin_password
    end
    credentials["url"] = "amqp://#{credentials["user"]}:#{credentials["pass"]}@#{credentials["host"]}:#{credentials["port"]}/#{credentials["vhost"]}"
    credentials
  end

  def gen_admin_credentials(instance)
    credentials = {
      "admin_port"  => instance.admin_port,
      "username" => instance.admin_username,
      "password" => instance.admin_password,
    }
  end

  def instance_dir(instance_id)
    File.join(@base_dir, instance_id)
  end

  def instance_log_dir(instance_id)
    File.join(@mssb_log_dir, instance_id)
  end
end
