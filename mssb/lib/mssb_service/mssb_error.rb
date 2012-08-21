# Copyright (c) 2009-2011 VMware, Inc.

module VCAP
  module Services
    module MSSB
      class MSSBError < VCAP::Services::Base::Error::ServiceError
        # 31300 - 31399  MSSB-specific Error
        MSSB_SAVE_INSTANCE_FAILED         = [31300, HTTP_INTERNAL,  "Could not save instance: %s"]
        MSSB_DESTORY_INSTANCE_FAILED      = [31301, HTTP_INTERNAL,  "Could not destroy instance: %s"]
        MSSB_FIND_INSTANCE_FAILED         = [31302, HTTP_NOT_FOUND, "Could not find instance: %s"]
        MSSB_START_INSTANCE_FAILED        = [31303, HTTP_INTERNAL,  "Could not start instance: %s"]
        MSSB_STOP_INSTANCE_FAILED         = [31304, HTTP_INTERNAL,  "Could not stop instance: %s"]
        MSSB_CLEANUP_INSTANCE_FAILED      = [31305, HTTP_INTERNAL,  "Could not cleanup instance, the reasons: %s"]
        MSSB_INVALID_PLAN                 = [31306, HTTP_INTERNAL,  "Invalid plan: %s"]
        MSSB_ADD_GROUP_FAILED             = [31309, HTTP_INTERNAL,  "Could not add group: %s"]
        MSSB_MODIFY_USER_FAILED           = [31310, HTTP_INTERNAL,  "Could not modify user: %s"]
        MSSB_ADD_USER_FAILED              = [31311, HTTP_INTERNAL,  "Could not add user: %s"]
        MSSB_DELETE_USER_FAILED           = [31312, HTTP_INTERNAL,  "Could not delete user: %s"]
        MSSB_ADD_USER_TO_GROUP_FAILED     = [31314, HTTP_INTERNAL,  "Could not add user %s to group %s"]
        MSSB_SAVE_USER_FAILED             = [31321, HTTP_INTERNAL,  "Could not save binduser: %s"]
      end
    end
  end
end
