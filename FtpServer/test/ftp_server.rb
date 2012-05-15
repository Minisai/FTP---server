require "socket"

class FTPServer
   def initialize(conf)
    @rnto_file = nil
    @config = {
      :host => 'localhost',
      :port => 21,
      :root => nil
      }.merge(conf)
    #raise(ArgumentError, "Root object must not be null.") unless @config[:root]
    @server = TCPServer.new(@config[:host], @config[:port])
   end

   class DummyLogger
    def method_missing(method_name, *args, &block); end
   end

   # Returns logger
   def log
    return @config[:logger] if @config[:logger]
    return DummyLogger.new
   end

   def not_implemented
    status(500);
   end

   def run
    threads = []
    log.debug "Waiting for connection"
    while (session = @server.accept)
      log.debug "Accepted connection from #{session.addr.join(', ')}"
      threads << Thread.new(session) do |s|
        thread[:socket] = s
        client_loop
      end
    end
    threads.each {|t| t.join }
   end

   private

   def thread
    Thread.current
   end

   def client_loop
    thread[:authenticated] = false
    thread[:cwd] = @config[:root]
    status(220, "Ruby FTP Server ready")
    while (thread[:socket] && (s = thread[:socket].gets))
      s.chomp!                        # remove record separator from the end of str
      log.debug "Request: #{s}"
      params = s.split(' ', 2)
      command = params.first
      command.downcase! if command
      m = 'cmd_'+command.to_s
      if self.respond_to?(m, true)
        puts m
        self.send(m, params[1])
      else
        status(500);
      end
    end
    thread[:socket].close if thread[:socket] and not thread[:socket].closed?
    thread[:socket] = nil
    thread[:data_socket].close if thread[:data_socket] and not thread[:data_socket].closed?
    thread[:data_socket] = nil
   end

   def status(code, info = nil)
     unless (info.nil?)
      log.debug "Response: " + code.to_s + ' ' + info
      thread[:socket].puts code.to_s + ' ' + info + "\r\n"
      return
     end
    case (code.to_i)
    when 125
      status(code, 'Data connection already open; transfer starting.')
    when 150
      status(code, 'File status okay; about to open data connection.')
    when 200
      status(code, 'Command okey.')
    when 226
      status(code, 'Closing data connection.')
    when 230
      status(code, 'User logged in, proceed.')
    when 250
      status(code, 'Requested file action okay, completed.')
    when 331
      status(code, 'User name okay, need password.')
    when 425
      status(code, "Can't open data connection.")
    when 500
      status(code, 'Syntax error, command unrecognized.')
    when 502
      status(code, 'Command not implemented.')
    when 530
      status(code, 'Not logged in.')
    when 550
      status(code, 'Requested action not taken.')
    else
      status(code, '')
    end
   end

   def data_connection(&block)
    client_socket = nil
    if (thread[:passive])
      unless (IO.select([thread[:data_socket]], nil, nil, 60000))
        status 425
        return false
      end
      client_socket = thread[:data_socket].accept
      status 150
    else
      client_socket = thread[:data_socket]
      status 125
    end
    yield(client_socket)
    return true
  ensure
    client_socket.close if client_socket && thread[:passive]
    client_socket = nil
   end

   def open_object(path)
    if (path[0,1] == '/') || (path.is_a?(Array) && (path[0] == ''))
      dir = @config[:root]
    else
      dir = thread[:cwd]
    end
    path = path.split('/') unless path.is_a?(Array)
    return dir if path.empty?
    last_element = path.pop
    path.each do |p|
      unless p == ''
        dir = dir.ftp_list.detect {|d| (d.ftp_name.casecmp(p) == 0) && (d.ftp_dir) }
        return nil unless dir
      end
    end
    dir = dir.ftp_list.detect {|d| (d.ftp_name.casecmp(last_element) == 0) } unless last_element == ''
    return dir
  end

  def open_path(path)
    result = open_object(path)
    result = nil if result && !result.ftp_dir
    return result
  end

  def open_file(path)
    result = open_object(path)
    result = nil if result && result.ftp_dir
    return result
  end

  def get_path(object)
    return '/' unless object
    return '/' if object == @config[:root]
    result = ''
    while object do
      result = object.ftp_name + '/' + result
      object = object.ftp_parent
    end
    return result
  end

  def get_quoted_path(object)
    get_path(object).gsub('"', '""')
  end

  #commands
  def cmd_quit(params)
    status(200)
    thread[:socket].close
    thread[:socket] = nil
  end

  def cmd_user(params)
    thread[:user] = params
    status(331)
  end

  def cmd_pass(params)
    thread[:pass] = params
    if (thread[:user]!=nil && thread[:pass]!=nil)
      thread[:authenticated] = true
      status 230
    else
      status 530
    end
  end

  def cmd_pwd(params)
    status 257, "\"#{ get_path(thread[:cwd]).gsub('"', '""') }\" is the current directory"
  end

  def cmd_cdup(params)
    thread[:cwd] = thread[:cwd].ftp_parent
    thread[:cwd] = @config[:root] unless thread[:cwd]
    status(250, 'Directory successfully changed.')
  end

  def cmd_dele(path)
    if (!thread[:authenticated])
     status 530
     return
    end
    if (file = open_file(path)) && file.ftp_delete(false)
      status 250
    else
      status(550, 'Delete operation failed.')
    end
  end

  def cmd_feat(params)
    thread[:socket].puts "211-Features\r\n"
    thread[:socket].puts " UTF8\r\n"
    thread[:socket].puts "211 end\r\n"
  end

  def cmd_list(params)
    data_connection do |data_socket|
      list = thread[:cwd].ftp_list
      list.each {|file| data_socket.puts((file.ftp_dir ? 'd': '-') + 'rw-rw-rw- 1 ftp ftp ' + file.ftp_size.to_s + ' ' + file.ftp_date.strftime('%b %d %H:%M') + ' ' + file.ftp_name + "\r\n") }
    end
    thread[:data_socket].close if thread[:data_socket]
    thread[:data_socket] = nil

    status 226, "Transfer complete"
  end

  def cmd_mdtm(path)
    if (file = open_file(path))
      status 213, file.ftp_date.strftime('%Y%m%d%H%M%S')
    else
      status(550, 'Could not get modification time.')
    end
  end

  def cmd_mkd(path)
    if (!thread[:authenticated])
     status 530
     return
    end
    dir = open_object(path)
    if (dir)
      status 521, "Directory already exists"
      return
    end
    splitted_path = path.split('/')
    mkdir = splitted_path.pop
    dir = open_path(splitted_path)
    if dir && (newone = dir.ftp_create(mkdir, true))
      status 257, "\"#{ get_path(thread[:cwd]).gsub('"', '""') +path }\" directory created."            #KOKO"\"#{ get_path(thread[:cwd]).gsub('"', '""') }\"
    else
      status 550
    end
  end

  def cmd_cwd(path)
    if path == '' || !path
      status(550, 'Failed to change directory.')
      return
    end
    if (newpath = open_path(path))
      thread[:cwd] = newpath
      status(250, 'Directory successfully changed.')
    else
      status(550, 'Failed to change directory.')
    end
  end

  def cmd_rmd(path)
    if (!thread[:authenticated])
     status 530
     return
    end
    if (dir = open_path(path)) && dir.ftp_delete(true)
      status 250
    else
      status(550, 'Remove directory operation failed.')
    end
  end

 def cmd_port(ip_port)
    s = ip_port.split(',')
    port = s[4].to_i * 256 + s[5].to_i
    host = s[0..3].join('.')
    if thread[:data_socket]
      thread[:data_socket].close
      thread[:data_socket] = nil
    end
    thread[:data_socket] = TCPSocket.new(host, port)
    thread[:passive] = false
    status 200, "Passive connection established (#{port})"
  end

  def cmd_pasv(params)
    if thread[:data_socket]
      thread[:data_socket].close
      thread[:data_socket] = nil
    end
    thread[:data_socket] = TCPServer.new('localhost', 0)
    thread[:passive] = true
    port = thread[:data_socket].addr[1]
    port_lo = port & "0x00FF".hex
    port_hi = port >> 8
    ip = thread[:data_socket].addr[3]
    ip = ip.split('.')
    status 227, "Entering Passive Mode (#{ip[0]},#{ip[1]},#{ip[2]},#{ip[3]},#{port_hi},#{port_lo})"
  end

  def cmd_retr(path)
    if (!thread[:authenticated])
     status 530
     return
    end
    if (file = open_file(path))
      data_connection do |data_socket|
        if file.ftp_retrieve(data_socket)
          status 226, 'Transfer complete'
        else
          status(550, 'Failed to open file.')
        end
      end
    else
      status(550, 'Failed to open file.')
    end

    thread[:data_socket].close if thread[:data_socket]
    thread[:data_socket] = nil
  end

  def cmd_size(path)
    if (file = open_file(path))
      status 213, file.ftp_size.to_s
    else
      status(550, 'Could not get file size.')
    end
  end

  def cmd_stor(path)
    if (!thread[:authenticated])
     status 530
     return
    end
    file = open_file(path)
    if file
      status 553, 'Could not create file.'
      return
    end
    unless file
      splitted_path = path.split('/')
      filename = splitted_path.pop
      dir = open_path(splitted_path)
      file = dir.ftp_create(filename) if dir
    end
    if file
      data_connection do |data_socket|
        file.ftp_store(data_socket)
      end
      status 226, 'Transfer complete'
    else
      status 550, 'Failed to open file.'
    end

    thread[:data_socket].close if thread[:data_socket]
    thread[:data_socket] = nil
  end

  def cmd_syst(params)
    status(215, RUBY_PLATFORM)
  end

  def cmd_type(type)
    status 200, "Type set."
  end

  def cmd_rnfr(path)
    if (!thread[:authenticated])
     status 530
     return
    end
    if (@rnto_file = open_file(path))
      status(350, 'Rename from accepted. Waiting for RNTO')
    else
      if(@rnto_file = open_path(path))
        status(350, 'Rename from accepted. Waiting for RNTO')
      else
        status(550, 'File doesnt exist')
      end
    end
  end

  def cmd_rnto(name)
    if (!thread[:authenticated])
     status 530
     return
    end
    if(!@rnto_file)
      status(400, 'RNTO requires a valid previous RNFR')
    else
      if (@rnto_file.ftp_rename(name))
        status(250, 'File renamed')
      else
        status(550, 'RNTO error')
      end
      @rnto_file = nil
    end
  end

end