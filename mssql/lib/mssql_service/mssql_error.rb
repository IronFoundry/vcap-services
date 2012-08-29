# Copyright (c) 2009-2011 VMware, Inc.

class VCAP::Services::MSSQL::MSSQLError < VCAP::Services::Base::Error::ServiceError
  MSSQL_DISK_FULL        = [32101, HTTP_INTERNAL, 'Node disk is full.']
  MSSQL_CONFIG_NOT_FOUND = [32102, HTTP_NOT_FOUND, 'MSSQL configuration %s not found.']
  MSSQL_CRED_NOT_FOUND   = [32103, HTTP_NOT_FOUND, 'MSSQL credential %s not found.']
  MSSQL_LOCAL_DB_ERROR   = [32104, HTTP_INTERNAL, 'MSSQL node local db error.']
  MSSQL_INVALID_PLAN     = [32105, HTTP_INTERNAL, 'Invalid plan %s.']
  MSSQL_SQLCMD_NOT_FOUND = [32105, HTTP_NOT_FOUND, 'Could not find sqlcmd.exe']
  MSSQL_CREATE_DB_FAILED = [32106, HTTP_INTERNAL, 'Could not create db %s']
  MSSQL_CREATE_LOGIN_FAILED = [32107, HTTP_INTERNAL, 'Could not create a DB login.']
  MSSQL_DROP_DB_FAILED = [32108, HTTP_INTERNAL, 'Could not drop db %s']
  MSSQL_DROP_LOGIN_FAILED = [32107, HTTP_INTERNAL, 'Could not drop a DB login.']
  MSSB_INVALID_PLAN       = [32108, HTTP_INTERNAL,  "Invalid plan: %s"]
end
