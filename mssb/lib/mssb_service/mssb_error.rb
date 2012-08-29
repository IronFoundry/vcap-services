# Copyright (c) 2009-2011 VMware, Inc.

module VCAP
  module Services
    module MSSB
      class MSSBError < VCAP::Services::Base::Error::ServiceError
        # 32000 - 32099  MSSB-specific Error
        MSSB_SAVE_INSTANCE_FAILED         = [32000, HTTP_INTERNAL,  "Could not save instance: %s"]
        MSSB_DESTORY_INSTANCE_FAILED      = [32001, HTTP_INTERNAL,  "Could not destroy instance: %s"]
        MSSB_FIND_INSTANCE_FAILED         = [32002, HTTP_NOT_FOUND, "Could not find instance: %s"]
        MSSB_START_INSTANCE_FAILED        = [32003, HTTP_INTERNAL,  "Could not start instance: %s"]
        MSSB_STOP_INSTANCE_FAILED         = [32004, HTTP_INTERNAL,  "Could not stop instance: %s"]
        MSSB_CLEANUP_INSTANCE_FAILED      = [32005, HTTP_INTERNAL,  "Could not cleanup instance, the reasons: %s"]
        MSSB_INVALID_PLAN                 = [32006, HTTP_INTERNAL,  "Invalid plan: %s"]
        MSSB_ADD_GROUP_FAILED             = [32009, HTTP_INTERNAL,  "Could not add group: %s"]
        MSSB_MODIFY_USER_FAILED           = [32010, HTTP_INTERNAL,  "Could not modify user: %s"]
        MSSB_ADD_USER_FAILED              = [32011, HTTP_INTERNAL,  "Could not add user: %s"]
        MSSB_DELETE_USER_FAILED           = [32012, HTTP_INTERNAL,  "Could not delete user: %s"]
        MSSB_ADD_USER_TO_GROUP_FAILED     = [32014, HTTP_INTERNAL,  "Could not add user %s to group %s"]
        MSSB_SAVE_USER_FAILED             = [32021, HTTP_INTERNAL,  "Could not save binduser: %s"]
      end
    end
  end
end
