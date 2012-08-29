require 'erb'
require 'tempfile'

require 'mssql_service/class_patches'

module VCAP
  module Services
    module MSSQL
      class BaseSqlcmdTemplateData; end
      class CreateDatabaseTemplateData < BaseSqlcmdTemplateData; end
      class DropDatabaseTemplateData < BaseSqlcmdTemplateData; end
      class CreateLoginTemplateData < BaseSqlcmdTemplateData; end
      class DropLoginTemplateData < BaseSqlcmdTemplateData; end
    end
  end
end

class VCAP::Services::MSSQL::BaseSqlcmdTemplateData
  
  attr_reader :sqlcmd_output_file
  attr_reader :sqlcmd_error_output_file

  def initialize(template_file)
    @erb = ERB.new(File.read(template_file))
    @sqlcmd_output_file = get_temp_file
    @sqlcmd_error_output_file = get_temp_file
  end

  def to_sql
    @erb.result(Kernel.binding)
  end

  def has_error?
    begin
      sz = File.size?(@sqlcmd_error_output_file)
      if sz.nil?
        false
      else
        sz > 0
      end
    rescue Errno::ENOENT
      false
    end
  end

  def error_output
    begin
      File.read(@sqlcmd_error_output_file)
    rescue Errno::ENOENT
      nil
    end
  end

  private
  def get_temp_file
    rv = Tempfile.new('sqlcmd_output_')
    rv.close
    rv.path.gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
  end

end

class VCAP::Services::MSSQL::CreateDatabaseTemplateData

  attr_reader :base_dir
  attr_reader :db_name
  attr_reader :db_initial_size_kb
  attr_reader :db_max_size_mb
  attr_reader :db_initial_log_size_kb
  attr_reader :db_max_log_size_mb

  def initialize(template_file, base_dir, db_name, init_sz_mb, max_sz_mb)
    super(template_file)
    @base_dir = WinMethods.winpath(base_dir)
    @db_name = db_name
    @db_initial_size_kb = init_sz_mb * 1024
    @db_initial_log_size_kb = @db_initial_size_kb
    @db_max_size_mb = max_sz_mb
    @db_max_log_size_mb = @db_max_size_mb * 2
  end
end

class VCAP::Services::MSSQL::CreateLoginTemplateData

  attr_reader :db_name
  attr_reader :db_user
  attr_reader :db_password

  def initialize(template_file, db_name, db_user, db_password)
    super(template_file)
    @db_name = db_name
    @db_user = db_user
    @db_password = db_password
  end
end

class VCAP::Services::MSSQL::DropDatabaseTemplateData

  attr_reader :db_name

  def initialize(template_file, db_name)
    super(template_file)
    @db_name = db_name
  end
end

class VCAP::Services::MSSQL::DropLoginTemplateData

  attr_reader :db_name
  attr_reader :db_user

  def initialize(template_file, db_name, db_user)
    super(template_file)
    @db_name = db_name
    @db_user = db_user
  end
end
