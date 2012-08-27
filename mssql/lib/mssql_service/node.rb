# Copyright (c) 2011 Tier3, Inc.
require 'erb'
require 'fileutils'
require 'logger'
require 'pp'

require 'datamapper'
require 'uuidtools'
require 'open3'
require 'tiny_tds'

module VCAP
  module Services
    module Mssql
      class Node < VCAP::Services::Base::Node
      end
    end
  end
end

require "mssql_service/common"
require "mssql_service/util"
require "mssql_service/storage_quota"
require "mssql_service/mssql_error"

class VCAP::Services::Mssql::Node

  KEEP_ALIVE_INTERVAL = 15
  STORAGE_QUOTA_INTERVAL = 1

  include VCAP::Services::Mssql::Util
  include VCAP::Services::Mssql::Common
  include VCAP::Services::Mssql

  class ProvisionedService
    include DataMapper::Resource
    property :name,       String,   :key => true
    property :user,       String,   :required => true
    property :password,   String,   :required => true
    # property plan is deprecated. The instances in one node have same plan.
    property :plan,       Integer,  :required => true
    property :quota_exceeded,  Boolean, :default => false
  end

  def initialize(options)
    super(options)

    @mssql_config = options[:mssql]
    @sqlcmd_bin = options[:sqlcmd_bin]
    @connection_wait_timeout = options[:connection_wait_timeout]

    @base_dir = options[:base_dir]
    FileUtils.mkdir_p(@base_dir) if @base_dir

    # TODO @available_storage = options[:available_storage] * 1024 * 1024
    @available_storage = 1024 * 1024 * 1024

    # ProvisionedService.all.each do |provisioned_service|
    #   @available_storage -= storage_for_service(provisioned_service)
    # end

    @long_queries_killed=0
    @long_tx_killed=0
    @provision_served=0
    @binding_served=0
  end

  def pre_send_announcement
    @tds_client = mssql_connect
    EM.add_periodic_timer(KEEP_ALIVE_INTERVAL) { mssql_keep_alive }

    # keep_alive_interval = KEEP_ALIVE_INTERVAL
    # keep_alive_interval = [keep_alive_interval, @connection_wait_timeout.to_f/2].min if @connection_wait_timeout
    # EM.add_periodic_timer(@max_long_query.to_f/2) { EM.defer{kill_long_queries} } if @max_long_query > 0
    # if (@max_long_tx > 0)
    #   EM.add_periodic_timer(@max_long_tx.to_f/2) { EM.defer{kill_long_transaction} }
    # else
    #   @logger.info("long transaction killer is disabled.")
    # end
    # EM.add_periodic_timer(STORAGE_QUOTA_INTERVAL) { EM.defer {enforce_storage_quota} }

    @queries_served = 0
    @qps_last_updated = 0

    # initialize qps counter
    # TODO get_qps

    DataMapper.setup(:default, options[:local_db])
    DataMapper::auto_upgrade!

    @capacity_lock.synchronize do
      ProvisionedService.all.each do |provisionedservice|
        @capacity -= capacity_unit
      end
    end

    check_db_consistency
  end

  def announcement
    @capacity_lock.synchronize do
      { :available_capacity => @capacity,
        :capacity_unit => capacity_unit }
    end
  end

  def check_db_consistency()

    db_names = []
    result = client.execute('exec [master].[sys].[sp_databases]')
    result.each do |row|
      db_names << row['DATABASE_NAME']
    end

    db_list = []
    db_names.each do |db_name|
      usr_rslt = client.execute("exec [#{db_name}].[sys].[sp_helpuser]")
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

  # def storage_for_service(provisioned_service)
  #   case provisioned_service.plan
  #   when :free then @max_db_size
  #   else
  #     raise MssqlError.new(MssqlError::MSSQL_INVALID_PLAN, provisioned_service.plan)
  #   end
  # end

  def mssql_connect
    host, user, password, port = %w{host user pass port}.map { |opt| @mssql_config[opt] }

    5.times do
      begin
        return TinyTds::Client.new(
          :username => user, :password => password,
          :host => host, :port => port, :login_timeout => @connection_wait_timeout)
      rescue TinyTds::Error => e
        @logger.error("MSSQL connection attempt to '#{host}' failed: #{e.to_s}")
        sleep(5)
      end
    end

    @logger.fatal("MSSQL connection unrecoverable")
    shutdown
    exit
  end

  #keep connection alive, and check db liveness
  def mssql_keep_alive
    if @tds_client.active?
      result = @tds_client.execute('SELECT @@VERSION AS [VERSION]')
      result.each(:as => :array, :cache_rows => false, :first => true) do |row|
        @logger.debug("mssql_keep_alive: '#{row[0]}'"
      end
    else
      @tds_client.close
      @tds_client = mssql_connect
    end
  rescue TinyTds::Error => e
    @logger.warn("MSSQL connection error: #{e.to_s}")
    @tds_client = mssql_connect
  end

  def kill_long_queries
    @logger.debug("kill_long_queries NOOP")
  #   process_list = @tds_client.list_processes
  #   process_list.each do |proc|
  #     thread_id, user, _, db, command, time, _, info = proc
  #     if (time.to_i >= @max_long_query) and (command == 'Query') and (user != 'root') then
  #       @tds_client.query("KILL QUERY " + thread_id)
  #       @logger.warn("Killed long query: user:#{user} db:#{db} time:#{time} info:#{info}")
  #       @long_queries_killed += 1
  #     end
  #   end
  # rescue TinyTds::Error => e
  #   @logger.error("MSSQL error: #{e.to_s}")
  end

  def kill_long_transaction
    @logger.debug("kill_long_transaction NOOP")
  #   query_str = "SELECT * from ("+
  #               "  SELECT trx_started, id, user, db, info, TIME_TO_SEC(TIMEDIFF(NOW() , trx_started )) as active_time" +
  #               "  FROM information_schema.INNODB_TRX t inner join information_schema.PROCESSLIST p " +
  #               "  ON t.trx_mssql_thread_id = p.ID " +
  #               "  WHERE trx_state='RUNNING' and user!='root' " +
  #               ") as inner_table " +
  #               "WHERE inner_table.active_time > #{@max_long_tx}"
  #   result = @tds_client.query(query_str)
  #   result.each do |trx|
  #     trx_started, id, user, db, info, active_time = trx
  #     @tds_client.query("KILL QUERY #{id}")
  #     @logger.warn("Kill long transaction: user:#{user} db:#{db} thread:#{id} info:#{info} active_time:#{active_time}")
  #     @long_tx_killed +=1
  #   end
  # rescue => e
  #   @logger.error("Error during kill long transaction: #{e}.")
  end

  def provision(plan, credential=nil)
    provisioned_service = ProvisionedService.new
    if credential
      name, user, password = %w(name user password).map{|key| credential[key]}
      provisioned_service.name = name
      provisioned_service.user = user
      provisioned_service.password = password
    else
      # mssql database name should start with alphabet character
      provisioned_service.name = 'd' + UUIDTools::UUID.random_create.to_s.delete('-')
      provisioned_service.user = 'u' + generate_credential
      provisioned_service.password = 'p' + generate_credential
    end
    provisioned_service.plan = plan

    create_database(provisioned_service)

    if not provisioned_service.save
      @logger.error("Could not save entry: #{provisioned_service.errors.inspect}")
      raise MssqlError.new(MssqlError::MSSQL_LOCAL_DB_ERROR)
    end
    response = gen_credential(provisioned_service.name, provisioned_service.user, provisioned_service.password)

    # TODO T3CF @provision_served += 1
    return response
  rescue => e
    delete_database(provisioned_service)
    raise
  end

  def unprovision(name, credentials)
    return if name.nil?
    @logger.debug("Unprovision database:#{name}, bindings: #{credentials.inspect}")
    provisioned_service = ProvisionedService.get(name)
    raise MssqlError.new(MssqlError::MSSQL_CONFIG_NOT_FOUND, name) if provisioned_service.nil?
    # TODO: validate that database files are not lingering
    # Delete all bindings, ignore not_found error since we are unprovision
    begin
      credentials.each{ |credential| unbind(credential)} if credentials
    rescue =>e
      # ignore
    end
    delete_database(provisioned_service)
    # TODO storage = storage_for_service(provisioned_service)
    # @available_storage += storage
    if not provisioned_service.destroy
      @logger.error("Could not delete service: #{provisioned_service.errors.inspect}")
      raise MssqlError.new(MysqError::MSSQL_LOCAL_DB_ERROR)
    end
    @logger.debug("Successfully fulfilled unprovision request: #{name}")
    true
  end

  def bind(name, bind_opts, credential=nil)
    @logger.debug("Bind service for db:#{name}, bind_opts = #{bind_opts}")
    binding = nil
    begin
      service = ProvisionedService.get(name)
      raise MssqlError.new(MssqlError::MSSQL_CONFIG_NOT_FOUND, name) unless service
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
      response = gen_credential(name, binding[:user], binding[:password])
      @logger.debug("Bind response: #{response.inspect}")
      @binding_served += 1
      return response
    rescue => e
      delete_database_user(name, binding[:user]) if binding
      raise e
    end
  end

  def unbind(credential)
    return if credential.nil?
    @logger.debug("Unbind service: #{credential.inspect}")
    name, user, bind_opts,passwd = %w(name user bind_opts password).map{|k| credential[k]}
    service = ProvisionedService.get(name)
    raise MssqlError.new(MssqlError::MSSQL_CONFIG_NOT_FOUND, name) unless service
    # validate the existence of credential, in case we delete a normal account because of a malformed credential
    # TODO T3CF res = @tds_client.query("SELECT * from mssql.user WHERE user='#{user}' AND password=PASSWORD('#{passwd}')")
    # TODO T3CF raise MssqlError.new(MssqlError::MSSQL_CRED_NOT_FOUND, credential.inspect) if res.num_rows()<=0
    delete_database_user(name, user)
    true
  end

  def create_database(provisioned_service)
    name, password, user = [:name, :password, :user].map { |field| provisioned_service.send(field) }
    begin

      start = Time.now

      @logger.debug("Creating: #{provisioned_service.inspect}")

      db_file_name = File.join(@base_dir, "#{name}.mdf").gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
      db_log_file_name = File.join(@base_dir, "#{name}_log.ldf").gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)

      # TODO MAXSIZE from config
      create_statement = "CREATE DATABASE [#{name}] ON PRIMARY (NAME = N'#{name}', FILENAME = N'#{db_file_name}', SIZE = 4096KB, MAXSIZE = 64MB) LOG ON (NAME = N'#{name}_log', FILENAME = N'#{db_log_file_name}', SIZE = 4096KB, MAXSIZE = 128MB)"

      # TODO T3CF can't use parameters here due to use of sp_prepexec underneath, hmmm
      @logger.debug("CREATE STATEMENT: #{create_statement}")
      @tds_client.do(create_statement)

      create_database_user(name, user, password)

      # TODO storage = storage_for_service(provisioned_service)
      # @available_storage -= storage
      @logger.debug("Done creating #{provisioned_service.inspect}. Took #{Time.now - start}.")

    rescue TinyTds::Error => e
      @logger.warn("Could not create database or user: #{e.to_s}")
      throw
    end
  end

  def create_database_user(name, user, password)
      @logger.info("Creating credentials: #{user}/#{password} for database #{name}")
      @tds_client.do("CREATE LOGIN [#{user}] WITH PASSWORD = '#{password}', DEFAULT_DATABASE=[#{name}], CHECK_POLICY=OFF") # TODO T3CF can't use parameters here due to use of sp_prepexec underneath, hmmm
      @tds_client.do("USE [#{name}]; CREATE USER [#{user}] FOR LOGIN [#{user}]; EXEC [#{name}].[sys].[sp_addrolemember] 'db_owner', '#{user}'")
  end

  def delete_database(provisioned_service)
    name, user = [:name, :user].map { |field| provisioned_service.send(field) }
    begin
      delete_database_user(name, user)
      @logger.info("Deleting database: #{name}")
      @tds_client.do("USE [master]; ALTER DATABASE [#{name}] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [#{name}]")
    rescue TinyTds::Error => e
      @logger.fatal("Could not delete database: #{e.to_s}")
    end
  end

  def delete_database_user(name, user)
    @logger.info("Delete user #{user}")
    @tds_client.do("USE [#{name}]; DROP USER #{user}") # TODO T3CF can't use parameters here due to use of sp_prepexec underneath, hmmm
    @tds_client.do("DROP LOGIN #{user}")
    kill_user_session(user)
  rescue TinyTds::Error => e
    @logger.fatal("Could not delete user '#{user}': #{e.to_s}")
  end

  def kill_user_session(user)
    @logger.info("TODO Kill sessions of user: #{user}")
    # begin
    #   process_list = @tds_client.list_processes
    #   process_list.each do |proc|
    #     thread_id, user_, _, db, command, time, _, info = proc
    #     if user_ == user then
    #       @tds_client.query("KILL #{thread_id}")
    #       @logger.info("Kill session: user:#{user} db:#{db}")
    #     end
    #   end
    # rescue TinyTds::Error => e
    #   # kill session failed error, only log it.
    #   @logger.error("Could not kill user session.:#{e.to_s}")
    # end
  end

  # restore a given instance using backup file.
  def restore(name, backup_path)
    @logger.debug("TODO Restore db #{name} using backup at #{backup_path}")
    # service = ProvisionedService.get(name)
    # raise MssqlError.new(MssqlError::MSSQL_CONFIG_NOT_FOUND, name) unless service
    # # revoke write and lock privileges to prevent race with drop database.
    # @tds_client.query("UPDATE db SET insert_priv='N', create_priv='N',
    #                    update_priv='N', lock_tables_priv='N' WHERE Db='#{name}'")
    # @tds_client.query("FLUSH PRIVILEGES")
    # kill_database_session(name)
    # # mssql can't delete tables that not in dump file.
    # # recreate the database to prevent leave unclean tables after restore.
    # @tds_client.query("DROP DATABASE #{name}")
    # @tds_client.query("CREATE DATABASE #{name}")
    # # restore privileges.
    # @tds_client.query("UPDATE db SET insert_priv='Y', create_priv='Y',
    #                    update_priv='Y', lock_tables_priv='Y' WHERE Db='#{name}'")
    # @tds_client.query("FLUSH PRIVILEGES")
    # host, user, pass =  %w{host user pass}.map { |opt| @mssql_config[opt] }
    # path = File.join(backup_path, "#{name}.sql.gz")
    # cmd ="#{@gzip_bin} -dc #{path}|" +
    #   "#{@sqlcmd_bin} -h #{host} -u #{user} --password=#{pass}"
    # cmd += " -S #{socket}" unless socket.nil?
    # cmd += " #{name}"
    # o, e, s = exe_cmd(cmd)
    # if s.exitstatus == 0
    #   return true
    # else
    #   return nil
    # end
  rescue => e
    @logger.error("Error during restore #{e}")
    nil
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

  # Dump db content into given path
  # TODO TODO
  def dump_instance(prov_cred, binding_creds, dump_file_path)
    @logger.debug("TODO Dump instance #{prov_cred["name"]} request.")
    # name = prov_cred["name"]
    # host, user, password, port, socket =  %w{host user pass port socket}.map { |opt| @mssql_config[opt] }
    # dump_file = File.join(dump_file_path, "#{name}.sql")
    # @logger.info("Dump instance #{name} content to #{dump_file}")
    # cmd = "#{@mssqldump_bin} -h #{host} -u #{user} --password=#{password} --single-transaction #{name} > #{dump_file}"
    # o, e, s = exe_cmd(cmd)
    # if s.exitstatus == 0
    #   return true
    # else
    #   return nil
    # end
  rescue => e
    @logger.warn(e)
    nil
  end

  # Provision and import dump files
  # Refer to #dump_instance
  # TODO TODO
  def import_instance(prov_cred, binding_creds, dump_file_path, plan)
    @logger.debug("TODO Import instance #{prov_cred["name"]} request.")
  # @logger.info("Provision an instance with plan: #{plan} using data from #{prov_cred.inspect}")
  # provision(plan, prov_cred)
  # name = prov_cred["name"]
  # import_file = File.join(dump_file_path, "#{name}.sql")
  # host, user, password, port, socket =  %w{host user pass port socket}.map { |opt| @mssql_config[opt] }
  # @logger.info("Import data from #{import_file} to database #{name}")
  # cmd = "#{@sqlcmd_bin} --host=#{host} --user=#{user} --password=#{password} #{name} < #{import_file}"
  # o, e, s = exe_cmd(cmd)
  # if s.exitstatus == 0
  #   return true
  # else
  #   return nil
  # end
  rescue => e
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
    # Mssql don't need to modify binding info TODO?
    return [prov_cred, binding_creds_hash]
  rescue => e
    @logger.warn(e)
    []
  end

  # shell CMD wrapper and logger
  def exe_cmd(cmd, stdin=nil)
    @logger.debug("Execute shell cmd:[#{cmd}]")
    o, e, s = Open3.capture3(cmd, :stdin_data => stdin)
    if s.exitstatus == 0
      @logger.info("Execute cmd:[#{cmd}] successd.")
    else
      @logger.error("Execute cmd:[#{cmd}] failed. Stdin:[#{stdin}], stdout: [#{o}], stderr:[#{e}]")
    end
    return [o, e, s]
  end

  def gen_credential(name, user, passwd)
    response = {
      "name"     => name,
      "hostname" => @local_ip,
      "host"     => @local_ip,
      "port"     => @mssql_config['port'],
      "user"     => user,
      "username" => user,
      "password" => passwd,
    }
  end
end
