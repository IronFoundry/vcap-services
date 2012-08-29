#!/usr/bin/env ruby
# -*- mode: ruby -*-
#
# Copyright (c) 2009-2011 VMware, Inc.

require 'win32/daemon'
require 'win32/eventlog'

include Win32

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __FILE__)
require "bundler/setup"
require "vcap_services_base"

$LOAD_PATH.unshift File.join(File.dirname(__FILE__), '..', 'lib')

require './mssql_gatewaybin'

class Daemon
  def service_main
    begin
      @event_log = EventLog.open('Application')
      @instance = VCAP::Services::MSSQL::Gateway.new
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Starting mssql_gateway_svc.rb oid: #{@instance.object_id}")
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
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Stopping mssql_gateway_svc.rb oid: #{@instance.object_id}")
      @event_log.close
    rescue => e
      @event_log.report_event(:event_type => EventLog::INFO, :data => "Exception in stopping! ex: #{e.to_s} oid: #{@instance.object_id}")
    ensure
      exit # NB: use 'exit' as running parts depend on Kernel.at_exit
    end
  end
end

Daemon.mainloop
