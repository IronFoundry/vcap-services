# Copyright (c) 2009-2011 VMware, Inc.
require "rest_client"
require "json"

module VCAP
  module Services
    module MSSB
      module Util
        @mssb_timeout = 2 if @mssb_timeout == nil
        @local_ip = "127.0.0.1" if @local_ip == nil

        def create_resource(credentials)
          RestClient::Resource.new("http://#{credentials["username"]}:#{credentials["password"]}@#{@local_ip}:#{credentials["admin_port"]}/api", :timeout => @mssb_timeout)
        end

        def add_vhost(credentials, vhost)
          response = create_resource(credentials)["vhosts/#{vhost}"].put nil, :content_type => "application/json"
          raise MSSBError.new(MSSBError::MSSB_ADD_VHOST_FAILED, vhost) if response != ""
        end

        def delete_vhost(credentials, vhost)
          response = create_resource(credentials)["vhosts/#{vhost}"].delete
          raise MSSBError.new(MSSBError::MSSB_DELETE_VHOST_FAILED, vhost) if response != ""
        end

        def add_user(credentials, username, password)
          response = create_resource(credentials)["users/#{username}"].put "{\"password\":\"#{password}\", \"administrator\":true}", :content_type => "application/json"
          raise MSSBError.new(MSSBError::MSSB_ADD_USER_FAILED, username) if response != ""
        end

        def delete_user(credentials, username)
          response = create_resource(credentials)["users/#{username}"].delete
          raise MSSBError.new(MSSBError::MSSB_DELETE_USER_FAILED, username) if response != ""
        end

        def get_permissions_by_options(binding_options)
          # FIXME: binding options is not implemented, use the full permissions.
          @default_permissions
        end

        def get_permissions(credentials, vhost, username)
          response = create_resource(credentials)["permissions/#{vhost}/#{username}"].get
          JSON.parse(response)
        end

        def set_permissions(credentials, vhost, username, permissions)
          response = create_resource(credentials)["permissions/#{vhost}/#{username}"].put permissions, :content_type => "application/json"
          raise MSSBError.new(MSSBError::MSSB_SET_PERMISSIONS_FAILED, username, permissions) if response != ""
        end

        def clear_permissions(credentials, vhost, username)
          response = create_resource(credentials)["permissions/#{vhost}/#{username}"].delete
          raise MSSBError.new(MSSBError::MSSB_CLEAR_PERMISSIONS_FAILED, username) if response != ""
        end

        def get_vhost_permissions(credentials, vhost)
          response = create_resource(credentials)["vhosts/#{vhost}/permissions"].get
          JSON.parse(response)
        end

        def list_users(credentials)
          response = create_resource(credentials)["users"].get
          JSON.parse(response)
        end

        def list_queues(credentials, vhost)
          response = create_resource(credentials)["queues"].get
          JSON.parse(response)
        end

        def list_exchanges(credentials, vhost)
          response = create_resource(credentials)["exchanges"].get
          JSON.parse(response)
        end

        def list_bindings(credentials, vhost)
          response = create_resource(credentials)["bindings"].get
          JSON.parse(response)
        end

        def close_fds
          3.upto(get_max_open_fd) do |fd|
            begin
              IO.for_fd(fd, "r").close
            rescue
            end
          end
        end

        def get_max_open_fd
          max = 0

          dir = nil
          if File.directory?("/proc/self/fd/") # Linux
            dir = "/proc/self/fd/"
          elsif File.directory?("/dev/fd/") # Mac
            dir = "/dev/fd/"
          end

          if dir
            Dir.foreach(dir) do |entry|
              begin
                pid = Integer(entry)
                max = pid if pid > max
              rescue
              end
            end
          else
            max = 65535
          end

          max
        end

      end
    end
  end
end
