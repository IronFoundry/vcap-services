require 'tempfile'

class Tempfile
  def winpath
    path.gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
  end
end

module VCAP
  module Services
    module Mssql
      module Node
        class BaseSqlcmdTemplateData
        class CreateDatabaseTemplateData < BaseSqlcmdTemplateData
        class CreateLoginTemplateData < BaseSqlcmdTemplateData
      end
    end
  end
end

class VCAP::Services::Mssql::Node::BaseSqlcmdTemplateData
  
  attr_reader :base_dir
  attr_reader :sqlcmd_output_file
  attr_reader :sqlcmd_error_output_file

  def initialize(base_dir)
    @base_dir = base_dir
    @sqlcmd_output_file = get_temp_file
    @sqlcmd_error_output_file = get_temp_file
  end

  def get_binding
    Kernel.binding
  end

  private
  def get_temp_file
    rv = Tempfile.new('sqlcmd_data_')
    rv.close
    rv.path.gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
  end

end

class VCAP::Services::Mssql::Node::CreateDatabaseTemplateData

  attr_reader :db_name
  attr_reader :db_initial_size_kb
  attr_reader :db_max_size_mb
  attr_reader :db_initial_log_size_kb
  attr_reader :db_max_log_size_mb

  def initialize(base_dir, db_name, init_sz_kb, max_sz_mb)
    super(base_dir)
    @db_name = db_name
    @db_initial_size_kb = init_sz_kb
    @db_initial_log_size_kb = @db_initial_size_kb
    @db_max_size_mb = max_sz_mb
    @db_max_log_size_mb = @db_max_size_mb * 2
  end
end

class VCAP::Services::Mssql::Node::CreateLoginTemplateData

  attr_reader :db_name
  attr_reader :db_user
  attr_reader :db_password

  def initialize(base_dir, db_name, db_user, db_password)
    super(base_dir)
    @db_name = db_name
    @db_user = db_user
    @db_password = db_password
  end
end
