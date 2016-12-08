#!/usr/bin/env ruby

require 'bundler/setup'
require 'msf/aggregator'

admin_host = '127.0.0.1'
admin_port = 2447
listener = '127.0.0.1'
remote_console = '127.0.0.1'

# server = Msf::Aggregator::Server.new('127.0.0.1', 1337)
server = Msf::Aggregator::MsgPackServer.new(admin_host, admin_port)
server.start

client = Msf::Aggregator::ServerProxy.new(admin_host, admin_port)
client.register_listener(listener, 8443, nil)
client.register_default(remote_console, 5000, nil)
client.stop

loop do
  command = $stdin.gets
  if command.chomp == 'exit'
      exit
  elsif command.chomp == 'clear'
    forwarder.requests = []
    forwarder.responses = []
  elsif command.chomp == 'pause'
    $stderr.puts "paused"
  elsif command.chomp == 'stop'
    server.stop
  elsif command.chomp == 'park'
    client.release_session($stdin.gets.chomp)
  end
end
