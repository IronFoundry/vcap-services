#!/usr/bin/env ruby
# -*- mode: ruby -*-
#
# Copyright (c) 2009-2011 VMware, Inc.

ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)
require 'bundler/setup'
require 'vcap_services_base'

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')
require 'mssb_service/mssb_provisioner'

class VCAP::Services::MSSB::Gateway < VCAP::Services::Base::Gateway

  def provisioner_class
    VCAP::Services::MSSB::Provisioner
  end

  def default_config_file
    config_base_dir = ENV['CLOUD_FOUNDRY_CONFIG_PATH'] || File.join(File.dirname(__FILE__), '..', 'config')
    File.join(config_base_dir, 'mssb_gateway.yml')
  end

end
