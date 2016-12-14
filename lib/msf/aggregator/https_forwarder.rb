require 'socket'
require 'openssl'
require 'msf/aggregator/logger'
require 'msf/aggregator/forwarder'

module Msf
  module Aggregator

    class HttpsForwarder < Forwarder
      CONNECTION_TIMEOUT = 60 # one minute

      attr_accessor :log_messages
      attr_accessor :requests
      attr_accessor :responses

      def initialize
        @ssl = true
        @ssl_version = 'TLS1'
        @requests = []
        @responses = []
        @request = ''
        @response = ''
        @log_messages = false
        @forward_routes = {}
        @inbound_connections = []
        @inbound_uris = {}
        @forwarder_mutex = Mutex.new
      end

      def add_route(rhost, rport, payload)
        forward = [rhost, rport]
        if payload.nil?
          @forward_routes['default'] = forward
          return
        end
        @forward_routes[payload] = forward
      end

      def forward(connection)
        tcp_client = ssl_client = nil
        peer_addr = connection.io.peeraddr[3]
        unless @inbound_connections.include? peer_addr
          @inbound_connections << peer_addr
        end

        #forward input requests
        # TODO: add uri routing selection here
        @request = ''
        request_lines = get_data(connection, false)
        uri = parse_uri(request_lines[0])
        @forwarder_mutex.synchronize do
          unless uri.nil?
            @inbound_uris[uri] = Time.now
          end
        end
        host, port = get_forward(uri)
        if host.nil?
          # when not forward found park the connection for now
          # in the future this may get smarter and return a 404 or something
          return send_parked_response(connection)
        end

        begin
          tcp_client = TCPSocket.new host, port
          ssl_context = OpenSSL::SSL::SSLContext.new
          ssl_context.ssl_version = :TLSv1
          ssl_client = OpenSSL::SSL::SSLSocket.new tcp_client, ssl_context
          ssl_client.connect
        rescue StandardError => e
          log 'error on console connect ' + e.to_s
          send_parked_response(connection)
          return
        end

        log 'connected to console'

        Thread.new do
          begin
            @response = ''
            request_lines = get_data(ssl_client, true)
            request_lines.each do |line|
              connection.puts line
              @response += line
            end
          rescue
            log $!
          end
          log "From console: \n" + @response
          @responses << @response if @log_messages
          ssl_client.sync_close = true
          ssl_client.close
          connection.sync_close = true
          connection.close
        end

        request_lines.each do |line|
          ssl_client.puts line
          @request += line
        end
        log "From victim: \n" + @request
        @requests << @request if log_messages
      end

      def connections
        # TODO: for now before reporting connections flush stale ones
        flush_stale_sessions
        connections = {}
        @inbound_uris.each do |connection|
          forward = 'parked'
          host, port = get_forward(connection)
          unless host.nil?
            forward = "#{host}:#{port}"
          end
          connections[connection] = forward
        end
        connections
      end

      def get_data(connection, guaranteed_length)
        checked_first = has_length = guaranteed_length
        content_length = 0
        request_lines = []

        while (input = connection.gets)
          request_lines << input
          # break for body read
          break if (input.inspect.gsub /^"|"$/, '').eql? '\r\n'

          if !checked_first && !has_length
            has_length = input.include?('POST')
            checked_first = true
          end

          if has_length && input.include?('Content-Length')
            content_length = input[(input.index(':') + 1)..input.length].to_i
          end

        end
        body = ''
        if has_length
          while body.length < content_length
            body += connection.read(content_length - body.length)
          end
          request_lines << body
        end
        request_lines
      end

      def get_forward(uri)
        unless @forward_routes[uri].nil?
          @forward_routes[uri]
        else
          @forward_routes['default']
        end
      end

      def flush_stale_sessions
        @forwarder_mutex.synchronize do
          stale_sessions = []
          @inbound_uris.each_pair do |uri, time|
            unless (time + CONNECTION_TIMEOUT) > Time.now
              stale_sessions << uri
            end
          end
          stale_sessions.each do |uri|
            @inbound_uris.delete(uri)
          end
        end
      end

      def parse_uri(http_request)
        parts = http_request.split(/ /)
        uri = nil
        if parts.length >= 2
          uri = http_request.split(/ /)[1]
          uri = uri.chomp('/')
        end
        uri
      end

      def log(message)
        Logger.log message if @log_messages
      end

      def send_parked_response(connection)
        log "sending parked response to #{connection.io.peeraddr[3]}"
        parked_message = []
        parked_message << 'HTTP/1.1 200 OK'
        parked_message << 'Content-Type: application/octet-stream'
        parked_message << 'Connection: close'
        parked_message << 'Server: Apache'
        parked_message << 'Content-Length: 0'
        parked_message << ' '
        parked_message << ' '
        parked_message.each do |line|
          connection.puts line
        end
        connection.sync_close = true
        connection.close
      end

      private :send_parked_response
      private :get_data
      private :get_forward
      private :log
    end
  end
end
