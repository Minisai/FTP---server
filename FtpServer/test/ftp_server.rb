require "socket"

class FTPServer
   def initialize(conf)
    @config = {
      :host => 'localhost',
      :port => 21,
      :root => nil
      }.merge(conf)
    #raise(ArgumentError, "Root object must not be null.") unless @config[:root]
    @server = TCPServer.new(@config[:host], @config[:port])
   end

   def log
    return @config[:logger] if @config[:logger]
    return EmptyLogger.new
   end

   class EmptyLogger
    def method_missing(method_name, *args, &block); end
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
    status(220, "Microsoft FTP Server ready")

    while (thread[:socket] && (s = thread[:socket].gets))
      s.chomp!                        # remove record separator from the end of str
      log.debug "Request: #{s}"
      params = s.split(' ', 2)
      command = params.first
      command.downcase! if command
      m = 'cmd_'+command.to_s
      if self.respond_to?(m, true)
        puts m;
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

end