module Metasploit
  module Aggregator
    module Http
      class Request
        attr_reader :headers
        attr_reader :body
        attr_reader :socket

        def initialize(request_headers, request_body, socket)
          @headers = request_headers
          @body = request_body
          @socket = socket
        end

        def self.parse_uri(http_request)
          req = http_request.headers[0]
          parts = req.split(/ /)
          uri = nil
          if parts.length >= 2
            uri = req.split(/ /)[1]
            uri = uri.chomp('/')
          end
          uri
        end

        # provide a default response in Request form
        def self.parked()
          generate_response(nil)
        end

        def self.generate_response(http_request)
          socket = nil
          body = ''
          unless http_request.nil? || http_request.body.nil?
            body = http_request.body
          end
          message_headers = []
          message_headers << 'HTTP/1.1 200 OK'
          message_headers << 'Content-Type: application/octet-stream'
          message_headers << 'Connection: close'
          message_headers << 'Server: Apache'
          message_headers << 'Content-Length: ' + body.length.to_s
          message_headers << ' '
          message_headers << ' '
          self.new(message_headers, body, socket)
        end
      end
    end
  end
end