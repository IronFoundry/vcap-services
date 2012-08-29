#!/usr/bin/env ruby
# -*- mode: ruby -*-
# Copyright (c) 2011 Tier 3, Inc.

require 'win32/daemon'
require 'win32/eventlog'

include Win32

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __FILE__)
require "bundler/setup"
require "vcap_services_base"

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require "mssql_service/mssql_node"

class VCAP::Services::MSSQL::NodeBin < VCAP::Services::Base::NodeBin

  def node_class
    VCAP::Services::MSSQL::Node
  end

  def default_config_file
    config_base_dir = ENV["CLOUD_FOUNDRY_CONFIG_PATH"] || File.join(File.dirname(__FILE__), '..', 'config')
    File.join(config_base_dir, 'mssql_node.yml')
  end

  def additional_config(options, config)
    options[:mssql] = parse_property(config, "mssql", Hash)
    options[:sqlcmd_bin] = parse_property(config, "sqlcmd_bin", String, :optional => true)

    # erb templates
    options[:db_create_template_file] = File.expand_path("../../resources/db_create.erb", __FILE__)
    options[:db_drop_template_file] = File.expand_path("../../resources/db_drop.erb", __FILE__)
    options[:db_login_create_template_file] = File.expand_path("../../resources/db_login_create.erb", __FILE__)
    options[:db_login_drop_template_file] = File.expand_path("../../resources/db_login_drop.erb", __FILE__)

    options[:max_db_size] = parse_property(config, "max_db_size", Integer)
    options[:max_long_query] = parse_property(config, "max_long_query", Integer)
    options[:max_long_tx] = parse_property(config, "max_long_tx", Integer)
    options[:kill_long_tx] = parse_property(config, "kill_long_tx", Boolean)
    options[:max_user_conns] = parse_property(config, "max_user_conns", Integer, :optional => true)
    options[:connection_pool_size] = parse_property(config, "connection_pool_size", Integer, :optional => true)
    options[:connection_wait_timeout] = parse_property(config, "connection_wait_timeout", Integer, :optional => true)
    options
  end

end

class Daemon
  def service_main
    begin
      @event_log = EventLog.open('Application')
      @instance = VCAP::Services::MSSQL::NodeBin.new
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Starting mssql_node_svc.rb oid: #{@instance.object_id}")
      @instance.start
    rescue => e
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Exception in starting! ex: #{e.to_s} oid: #{@instance.object_id}")
      exit!
    end
  end

  def service_stop
    stop
  end

  def service_shutdown
    stop
  end

  def stop
    begin
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Stopping mssql_node_svc.rb oid: #{@instance.object_id}")
      @instance.shutdown
      @event_log.report_event(:event_type => EventLog::INFO, :data => '@instance.shutdown complete')
      @event_log.close
    rescue => e
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Exception in stopping! ex: #{e.to_s} oid: #{@instance.object_id}")
    ensure
      exit
    end
  end
end

Daemon.mainloop
