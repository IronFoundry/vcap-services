#!/usr/bin/env ruby
# -*- mode: ruby -*-
# Copyright (c) 2009-2011 VMware, Inc.
ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../../Gemfile', __FILE__)
require 'bundler/setup'
require 'vcap_services_base'

$LOAD_PATH.unshift(File.expand_path('../../lib', __FILE__))
require 'mssb_service/mssb_node'

class VCAP::Services::MSSB::NodeBin < VCAP::Services::Base::NodeBin

  def node_class
    VCAP::Services::MSSB::Node
  end

  def default_config_file
    File.join(File.dirname(__FILE__), '..', 'config', 'mssb_node.yml')
  end

  def additional_config(options, config)
    options
  end

end
