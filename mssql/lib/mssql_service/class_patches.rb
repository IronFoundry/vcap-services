class File
  class << self
    alias orig_join join
    def join(*args)
      orig_join(*args).gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
    end
  end
end

class Tempfile
  def winpath
    path.gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
  end
end
