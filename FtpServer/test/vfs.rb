class FileSystem
  attr_reader :ftp_name, :ftp_size, :ftp_dir, :ftp_date, :ftp_parent

    def ftp_list
      output = Array.new
      Dir.entries(@path).sort.each do |file|
        if(file!='')
          output << FileSystem.new(@path + '/' + file, self)
        end
      end
      return output
    end

    def ftp_create(name, dir = false)
      if dir
        begin
          Dir.mkdir(@path + '/' + name)
          return true
        rescue
          return false
        end
      else
        FileSystem.new(@path + '/' + name, self)
      end
    end

    def ftp_retrieve(output)
      output << File.new(@path, 'r').read
    end

    def ftp_store(input)
      return false unless File.open(@path, 'w') do |f|
        f.write input.read
      end
      @ftp_size = File.size?(@path)
      @ftp_date = File.mtime(@path) if File.exists?(@path)
    end

    def ftp_delete(dir = false)
      if dir
        begin
        if Dir.rmdir(@path)
          return true
        end
        rescue SystemCallError
          return false
          end
      else
        if File.delete(@path)
          return true
        end
     end
      return false
    end

    def initialize(path, parent = nil)
      @path = path
      @ftp_parent = parent
      @ftp_name = path.split('/').last
      @ftp_name = '/' unless @ftp_name
      @ftp_name = '' unless path.split('/').length>2
      @ftp_dir = File.directory?(path)
      @ftp_size = File.size?(path)
      @ftp_size = 0 unless @ftp_size
      @ftp_date = Time.now
      @ftp_date = File.mtime(path) if File.exists?(path)
    end
end
