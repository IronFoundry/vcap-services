# Copyright (c) 2011 Tier3, Inc.
require 'erb'
require 'fileutils'
require 'logger'
require 'pp'

require 'datamapper'
require 'uuidtools'
require 'open3'
require 'tiny_tds'
require 'tempfile'

module VCAP
  module Services
    module MSSQL
      class Node < VCAP::Services::Base::Node; end
    end
  end
end

require 'mssql_service/common'
require 'mssql_service/util'
require 'mssql_service/mssql_error'
require 'mssql_service/template_data'
require 'mssql_service/class_patches'

class VCAP::Services::MSSQL::Node

  KEEP_ALIVE_INTERVAL = 15
  STORAGE_QUOTA_INTERVAL = 1

  include VCAP::Services::MSSQL::Util
  include VCAP::Services::MSSQL::Common
  include VCAP::Services::MSSQL

  class ProvisionedService
    include DataMapper::Resource
    property :name,           String,  :key => true
    property :user,           String,  :required => true
    property :password,       String,  :required => true
    property :quota_exceeded, Boolean, :default => false
  end

  def initialize(options)
    super(options)
    @hostname = get_host

    # database server credentials and info
    @mssql_config = options[:mssql]

    @sqlcmd_bin = verify_sqlcmd(options)
    @connection_wait_timeout_secs = options[:connection_wait_timeout]

    @db_create_template_file = options[:db_create_template_file]
    @db_drop_template_file = options[:db_drop_template_file]
    @db_login_create_template_file = options[:db_login_create_template_file]
    @db_login_drop_template_file = options[:db_login_drop_template_file]

    @base_dir = options[:base_dir]
    FileUtils.mkdir_p(@base_dir) if @base_dir

    @max_db_size_mb = options[:max_db_size] || 256 # Note: MB
    @initial_db_size_mb = options[:initial_db_size] || 4 # Note: MB

    @max_long_tx = options[:max_long_tx]

    # DataMapper::Logger.new($stdout, :debug)
    DataMapper.setup(:default, options[:local_db])
    DataMapper::auto_upgrade!

    @long_tx_killed = 0
  end

  def pre_send_announcement
    @tds_client = mssql_connect

    check_db_consistency

    @capacity_lock.synchronize do
      ProvisionedService.all.each do |provisionedservice|
        @capacity -= capacity_unit
      end
    end

    EM.add_periodic_timer(KEEP_ALIVE_INTERVAL) { mssql_keep_alive }
    EM.add_periodic_timer(@max_long_tx.to_f / 2) { kill_long_transaction } if @max_long_tx > 0
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity, :capacity_unit => capacity_unit }
    end
  end

  def check_db_consistency

    db_names = []
    result = @tds_client.execute('exec [master].[sys].[sp_databases]')
    result.each do |row|
      db_names << row['DATABASE_NAME']
    end

    db_list = []
    db_names.each do |db_name|
      usr_rslt = @tds_client.execute("exec [#{db_name}].[sys].[sp_helpuser]")
      usr_rslt.each do |row|
        db_user = row['UserName']
        db_list << [ db_name, db_user ]
      end
    end

    ProvisionedService.all.each do |service|
      db, user = service.name, service.user
      if not db_list.include?([db, user]) then
        @logger.error("Node database inconsistent!!! db:user <#{db}:#{user}> not in mssql.")
        next
      end
    end
  end

  def mssql_connect
    host, user, password, port = %w{host user pass port}.map { |opt| @mssql_config[opt] }

    5.times do
      begin
        return TinyTds::Client.new(
          :username => user, :password => password,
          :host => host, :port => port, :login_timeout => @connection_wait_timeout_secs)
      rescue TinyTds::Error => e
        @logger.error("MSSQL connection attempt to '#{host}' failed: #{e.to_s}")
        sleep(5)
      end
    end

    @logger.fatal("MSSQL connection unrecoverable")
    shutdown
    exit
  end

  def mssql_keep_alive
    if @tds_client.active?
      result = @tds_client.execute('SELECT @@VERSION AS [VERSION]')
      result.each(:as => :array, :cache_rows => false, :first => true) do |row|
        @logger.debug("mssql_keep_alive: '#{row[0]}'")
      end
    else
      @tds_client.close
      @tds_client = mssql_connect
    end
  rescue TinyTds::Error => e
    @logger.warn("MSSQL connection error: #{e.to_s}")
    @tds_client = mssql_connect
  end

  def provision(plan, credentials=nil, version=nil)
    raise MSSQLError.new(MSSQLError::MSSQL_INVALID_PLAN, plan) unless plan.to_s == @plan
    provisioned_service = ProvisionedService.new
    if credentials
      name, user, password = %w(name user password).map{ |key| credentials[key] }
      provisioned_service.name = name
      provisioned_service.user = user
      provisioned_service.password = password
    else
      # Note: mssql database name should start with alphabet character
      provisioned_service.name = 'd' + UUIDTools::UUID.random_create.to_s.delete('-')
      provisioned_service.user = 'u' + generate_credential
      provisioned_service.password = 'p' + generate_credential
    end

    create_database(provisioned_service)

    if not provisioned_service.save
      @logger.error("Could not save entry: #{provisioned_service.errors.inspect}")
      raise MSSQLError.new(MSSQLError::MSSQL_LOCAL_DB_ERROR)
    end
    response = gen_credentials(provisioned_service.name, provisioned_service.user, provisioned_service.password)

    return response
  rescue => e
    @logger.warn("Exception in provision: #{e}")
    delete_database(provisioned_service)
    raise
  end

  def unprovision(instance_id, credentials_list = [])
    @logger.debug("Unprovision database: #{instance_id}, bindings: #{credentials_list.inspect}")

    provisioned_service = get_instance(instance_id)

    begin
      credentials_list.each { |credential| unbind(credential) }
    rescue => e
      @logger.warn("Exception in unprovision: #{e}")
    end

    delete_database(provisioned_service)

    if not provisioned_service.destroy
      @logger.error("Could not delete service: #{provisioned_service.errors.inspect}")
      raise MSSQLError.new(MysqError::MSSQL_LOCAL_DB_ERROR)
    end

    @logger.debug("Successfully fulfilled unprovision request: #{instance_id}")

    true
  end

  def bind(name, bind_opts, credential=nil)
    @logger.debug("Bind service for db:#{name}, bind_opts = #{bind_opts}")
    binding = nil
    begin
      service = get_instance(name)
      # create new credential for binding
      binding = Hash.new
      if credential
        binding[:user] = credential["user"]
        binding[:password ]= credential["password"]
      else
        binding[:user] = 'u' + generate_credential
        binding[:password ]= 'p' + generate_credential
      end
      binding[:bind_opts] = bind_opts
      create_database_user(name, binding[:user], binding[:password])
      response = gen_credentials(name, binding[:user], binding[:password])
      @logger.debug("Bind response: #{response.inspect}")
      return response
    rescue => e
      @logger.warn("Exception in bind: #{e}")
      delete_database_user(name, binding[:user]) if binding
      raise e
    end
  end

  def unbind(credential)
    return if credential.nil?
    @logger.debug("Unbind service: #{credential.inspect}")
    name, user = %w(name user).map{ |k| credential[k] }
    service = get_instance(name)
    delete_database_user(name, user)
    true
  end

  def create_database(provisioned_service)
    name, password, user = [:name, :password, :user].map { |field| provisioned_service.send(field) }

    start = Time.now

    @logger.debug("Creating: #{provisioned_service.inspect}")

    tmpl_data = CreateDatabaseTemplateData.new(@db_create_template_file, @base_dir, name, @initial_db_size_mb, @max_db_size_mb)
    unless run_template(tmpl_data)
      raise MSSQLError.new(MSSQLError::MSSQL_CREATE_DB_FAILED, name)
    end

    create_database_user(name, user, password)

    @logger.debug("Done creating #{provisioned_service.inspect}. Took #{Time.now - start}.")
  end

  def create_database_user(name, user, password)
    @logger.info("Creating credentials: #{user}/#{password} for database #{name}")
    tmpl_data = CreateLoginTemplateData.new(@db_login_create_template_file, name, user, password)
    unless run_template(tmpl_data)
      raise MSSQLError.new(MSSQLError::MSSQL_CREATE_LOGIN_FAILED)
    end
  end

  def delete_database(provisioned_service)
    name = provisioned_service.name
    user = provisioned_service.user
    delete_database_user(name, user)
    @logger.info("Deleting database: #{name}")
    tmpl_data = DropDatabaseTemplateData.new(@db_drop_template_file, name)
    unless run_template(tmpl_data)
      @logger.warn("Error in dropping database #{name}.")
    end
  end

  def delete_database_user(name, user)
    @logger.info("Delete user #{user}")
    tmpl_data = DropLoginTemplateData.new(@db_login_drop_template_file, name, user)
    unless run_template(tmpl_data) # Ignore error
      @logger.warn("Error in dropping user #{user} from db #{name}.")
    end
  end

  # Disable all credentials and kill user sessions
  def disable_instance(prov_cred, binding_creds)
    @logger.debug("Disable instance #{prov_cred["name"]} request.")
    binding_creds << prov_cred
    binding_creds.each do |cred|
      unbind(cred)
    end
    true
  rescue  => e
    @logger.warn(e)
    nil
  end

  # Re-bind credentials
  # Refer to #disable_instance
  def enable_instance(prov_cred, binding_creds_hash)
    @logger.debug("Enable instance #{prov_cred["name"]} request.")
    name = prov_cred["name"]
    bind(name, nil, prov_cred)
    binding_creds_hash.each do |k, v|
      cred = v["credentials"]
      binding_opts = v["binding_options"]
      bind(name, binding_opts, cred)
    end
    # MSSQL don't need to modify binding info TODO?
    return [prov_cred, binding_creds_hash]
  rescue => e
    @logger.warn(e)
    []
  end

  def kill_long_transaction
    sql = <<-eosql
      SELECT * FROM (SELECT
        [session_id], [user_id],
        [database_id], ISNULL([total_elapsed_time]/1000,0) AS [elapsed_seconds],
        [query].[text]
      FROM
        [sys].[dm_exec_requests] [r]
      CROSS APPLY
        [sys].[dm_exec_sql_text]([r].[sql_handle]) AS [query]) AS [queries]
      WHERE
        [queries].[elapsed_seconds] >= #{@max_long_tx} AND
        [user_id] > 1 AND [database_id] > 4
    eosql
    result_set = @tds_client.execute(sql)
    killable = []
    result_set.each do |row|
      killable << [ row['session_id'], row['user_id'], row['text'] ]
    end
    killable.each do |k|
      session_id = k[0]
      @tds_client.execute("KILL #{session_id}")
      @logger.info("Killed user: #{k[1]} text: #{k[2]}")
      @long_tx_killed += 1
    end
  rescue TinyTds::Error => e
    @logger.warn("SQL error: #{e}")
  end

  def verify_sqlcmd(options)

    sqlcmd_bin = options[:sqlcmd_bin]

    if sqlcmd_bin.nil?
      sqlcmd_bin = search_path_for('sqlcmd.exe')
      if sqlcmd_bin.nil?
        raise MSSQLError.new(MSSQLError::MSSQL_SQLCMD_NOT_FOUND)
      end
    end

    begin
      o, e, s = exe_cmd(sqlcmd_bin, '-?')
      if s.nil? or not s.success?
        raise MSSQLError.new(MSSQLError::MSSQL_SQLCMD_NOT_FOUND)
      end
    rescue Errno::ENOENT => e
      @logger.error("Command not found: [#{e.to_s}]")
      raise MSSQLError.new(MSSQLError::MSSQL_SQLCMD_NOT_FOUND)
    end

    sqlcmd_bin
  end

  def exe_cmd(cmd, args)
    if cmd.include?(' ') and not cmd.start_with?('"')
      cmd = "\"#{cmd}\""
    end
    @logger.debug("Execute shell cmd: [#{cmd} #{args}]")
    o, e, s = Open3.capture3("#{cmd} #{args}")
    if s.success?
      @logger.debug('Execute cmd success.')
    else
      @logger.error("Execute cmd failed. stdout: [#{o}], stderr:[#{e}]")
    end
    return [o, e, s]
  end

  def search_path_for(cmd)
    path_entries = ENV['PATH'].split(';')
    path_entries.each do |pe|
      test_path = File.join(pe, cmd)
      if File.exists?(test_path)
        return test_path
      end
    end
  end

  def run_template(tmpl_data)

    sql_host = @mssql_config['host']
    sql_user = @mssql_config['user']
    sql_pass = @mssql_config['pass']

    sqlcmd_input_file = Tempfile.new('sqlcmd_input_')
    sqlcmd_rslt = true
    begin
      sql = tmpl_data.to_sql
      @logger.debug("Executing sql: #{sql}")
      sqlcmd_input_file.write(sql)
      sqlcmd_input_file.close
      infile = sqlcmd_input_file.winpath
      @logger.debug("Executing: #{@sqlcmd_bin} -S #{sql_host} -U #{sql_user} -P #{sql_pass} -i #{infile}")
      sqlcmd_rslt = system(@sqlcmd_bin, '-S', sql_host, '-U', sql_user, '-P', sql_pass, '-i', infile)
      if sqlcmd_rslt == false or tmpl_data.has_error?
        sqlcmd_rslt = false
        @logger.error("Error in sqlcmd: #{tmpl_data.error_output}")
      end
    ensure
      sqlcmd_input_file.unlink
    end
    return sqlcmd_rslt
  end

  def get_instance(instance_name)
    instance = ProvisionedService.get(instance_name)
    raise MSSQLError.new(MSSQLError::MSSQL_CONFIG_NOT_FOUND, instance_name) if instance.nil?
    instance
  end

  def gen_credentials(name, user, passwd)
    response = {
      "name"     => name,
      "hostname" => @hostname,
      "host"     => @hostname,
      "port"     => @mssql_config['port'],
      "user"     => user,
      "username" => user,
      "password" => passwd,
    }
  end
end
