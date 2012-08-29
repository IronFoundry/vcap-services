#!/usr/bin/env ruby
# -*- mode: ruby -*-
# Copyright (c) 2009-2011 VMware, Inc.

require 'mssql_service/mssql_node'

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
    options[:max_user_conns] = parse_property(config, "max_user_conns", Integer, :optional => true)

    options[:connection_pool_size] = parse_property(config, "connection_pool_size", Integer, :optional => true)
    options[:connection_wait_timeout] = parse_property(config, "connection_wait_timeout", Integer, :optional => true)
    options
  end

end
