require 'socket'
require 'openssl'
require 'msf/aggregator/forwarder'
require 'msf/aggregator/logger'
require 'msf/aggregator/router'

module Msf
  module Aggregator

    class HttpsForwarder < Forwarder
      CONNECTION_TIMEOUT = 60 # one minute

      attr_accessor :log_messages
      attr_reader :response_queues

      def initialize
        @log_messages = false
        @response_queues = {}
        @responding_threads = {}
        @forwarder_mutex = Mutex.new
        @router = Router.instance
      end

      def forward(connection)
        #forward input requests
        request_lines = URIResponder.get_data(connection, false)
        uri = parse_uri(request_lines[0])
        @forwarder_mutex.synchronize do
          unless uri.nil?
            unless @response_queues[uri]
              uri_responder = URIResponder.new(uri)
              uri_responder.log_messages = @log_messages
              @response_queues[uri] = uri_responder
            end
            @response_queues[uri].queue << Request.new(request_lines, connection)
            @response_queues[uri].time = Time.now
          else
            connection.sync_close = true
            connection.close
          end
        end
      end

      def connections
        # TODO: for now before reporting connections flush stale ones
        flush_stale_sessions
        connections = {}
        @response_queues.each_pair do |connection, queue|
          forward = 'parked'
          host, port = @router.get_forward(connection)
          unless host.nil?
            forward = "#{host}:#{port}"
          end
          connections[connection] = forward
        end
        connections
      end

      def flush_stale_sessions
        @forwarder_mutex.synchronize do
          stale_sessions = []
          @response_queues.each_pair do |uri, queue|
            unless (queue.time + CONNECTION_TIMEOUT) > Time.now
              stale_sessions << uri
            end
          end
          stale_sessions.each do |uri|
            @response_queues[uri].stop_processing
            @response_queues.delete(uri)
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

      class URIResponder
        attr_accessor :queue
        attr_accessor :time
        attr_accessor :log_messages
        attr_reader :uri

        def initialize(uri)
          @uri = uri
          @queue = Queue.new
          @thread = Thread.new { process_requests }
          @time = Time.now
          @router = Router.instance
        end

        def process_requests

          while true do
            begin
              request_task = @queue.pop
              connection = request_task.socket
              request_lines = request_task.request

              # peer_addr = connection.io.peeraddr[3]

              host, port = @router.get_forward(@uri)
              if host.nil?
                # when no forward found park the connection for now
                # in the future this may get smarter and return a 404 or something
                return send_parked_response(connection)
              end

              tcp_client = ssl_client = nil

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

              request_lines.each do |line|
                ssl_client.write line
              end
              # log "From victim: \n" + request_lines.join()

              begin
                response = ''
                request_lines = URIResponder.get_data(ssl_client, true)
                request_lines.each do |line|
                  connection.write line
                  response += line
                end
                # log "From console: \n" + response
              rescue
                log $!
              end
              ssl_client.sync_close = true
              ssl_client.close
              connection.sync_close = true
              connection.close
            rescue Exception => e
              log e.to_s
            end
          end

        end

        def stop_processing
          @thread.exit
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

        def self.get_data(connection, guaranteed_length)
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

        def log(message)
          Logger.log message if @log_messages
        end

        private :log
        private :send_parked_response
      end

      class Request
        attr_reader :request
        attr_reader :socket

        def initialize(request, socket)
          @request = request
          @socket = socket
        end
      end

    end
  end
end
