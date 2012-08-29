# Copyright (c) 2009-2011 VMware, Inc.
require 'mssb_service/common'

class VCAP::Services::MSSB::Provisioner < VCAP::Services::Base::Provisioner
  include VCAP::Services::MSSB::Common
end
