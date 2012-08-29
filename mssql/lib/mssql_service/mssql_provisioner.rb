# Copyright (c) 2009-2011 VMware, Inc.
require 'mssql_service/common'

class VCAP::Services::MSSQL::Provisioner < VCAP::Services::Base::Provisioner
  include VCAP::Services::MSSQL::Common
end
