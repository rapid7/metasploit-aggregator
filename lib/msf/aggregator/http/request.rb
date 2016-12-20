module Msf
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
      end
    end
  end
end