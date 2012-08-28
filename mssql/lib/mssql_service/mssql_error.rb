# Copyright (c) 2009-2011 VMware, Inc.

class VCAP::Services::Mssql::MssqlError < VCAP::Services::Base::Error::ServiceError
  MSSQL_DISK_FULL        = [31001, HTTP_INTERNAL, 'Node disk is full.']
  MSSQL_CONFIG_NOT_FOUND = [31002, HTTP_NOT_FOUND, 'Mssql configuration %s not found.']
  MSSQL_CRED_NOT_FOUND   = [31003, HTTP_NOT_FOUND, 'Mssql credential %s not found.']
  MSSQL_LOCAL_DB_ERROR   = [31004, HTTP_INTERNAL, 'Mssql node local db error.']
  MSSQL_INVALID_PLAN     = [31005, HTTP_INTERNAL, 'Invalid plan %s.']
  MSSQL_SQLCMD_NOT_FOUND = [31005, HTTP_NOT_FOUND, 'Could not find sqlcmd.exe']
  MSSQL_CREATE_DB_FAILED = [31006, HTTP_INTERNAL, 'Could not create db %s']
  MSSQL_CREATE_LOGIN_FAILED = [31007, HTTP_INTERNAL, 'Could not create a DB login.']
  MSSQL_DROP_DB_FAILED = [31008, HTTP_INTERNAL, 'Could not drop db %s']
  MSSQL_DROP_LOGIN_FAILED = [31007, HTTP_INTERNAL, 'Could not drop a DB login.']
end
