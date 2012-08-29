#!/usr/bin/env ruby
# -*- mode: ruby -*-
#
# Copyright (c) 2009-2011 VMware, Inc.

require 'mssql_service/mssql_provisioner'

class VCAP::Services::MSSQL::Gateway < VCAP::Services::Base::Gateway

  def provisioner_class
    VCAP::Services::MSSQL::Provisioner
  end

  def default_config_file
    config_base_dir = ENV['CLOUD_FOUNDRY_CONFIG_PATH'] || File.join(File.dirname(__FILE__), '..', 'config')
    File.join(config_base_dir, 'mssql_gateway.yml')
  end

end
