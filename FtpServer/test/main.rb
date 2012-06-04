require  './ftp_server'
require  './vfs'
# coding: utf-8
root = FileSystem.new("D:/") unless root = FileSystem.new(ARGV[0].to_s)
host = 'localhost' unless host = ARGV[1].to_s
port = 21 unless port = ARGV[2].to_i
#if(File.directory?("D:/"))
#  root = FileSystem.new("D:/")
#  if(!(port = ARGV[0].to_i))
#    port = 21
#  end
#else
#  root = FileSystem.new("/home")
#  if(!(port = ARGV[0].to_i))
#    port = 2121
#  end
#end

server = FTPServer.new(:root => root, :port => port, :host => host)
server.run
