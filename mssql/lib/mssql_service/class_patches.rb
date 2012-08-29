module WinMethods
  def WinMethods.winpath(path)
    path.gsub(File::SEPARATOR, File::ALT_SEPARATOR || File::SEPARATOR)
  end
end

class File
  class << self
    alias orig_join join
    def join(*args)
      WinMethods.winpath(orig_join(*args))
    end
  end
end

class Tempfile
  def winpath
    WinMethods.winpath(path)
  end
end
