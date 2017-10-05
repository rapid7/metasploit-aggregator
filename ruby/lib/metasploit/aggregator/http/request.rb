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
          message_headers << 'HTTP/1.1 200 OK' + "\n"
          message_headers << 'Content-Type: application/octet-stream' + "\n"
          message_headers << 'Connection: close' + "\n"
          message_headers << 'Server: Apache' + "\n"
          message_headers << 'Content-Length: ' + body.length.to_s + "\n"
          message_headers << '' + "\n"
          message_headers << '' + "\n"
          self.new(message_headers, body, socket)
        end

        def self.forge_request(uri, body, socket = nil)
          message_headers = []
          message_headers << "POST #{uri}/ HTTP/1.1" + "\n"
          message_headers << 'Accept-Encoding: identity' + "\n"
          message_headers << 'Content-Length: ' + body.length.to_s + "\n"
          message_headers << 'Host: 127.0.0.1:2447' + "\n" # this value is defaulted to reflect the aggregator
          message_headers << 'Content-Type: application/octet-stream' + "\n"
          message_headers << 'Connection: close' + "\n"
          message_headers << 'User-Agent: Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko'+ "\n"
          message_headers << '' + "\n"
          self.new(message_headers, body, socket)
        end

      end
    end
  end
end