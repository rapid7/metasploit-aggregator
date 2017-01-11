require "msf/aggregator/http/request"
require "msf/aggregator/http/responder"

module Msf
  module Aggregator
    module Http
      # a Requester takes in Request object and to send to a known port and protocol
      # and receives a response that it also returns as a Request object
      class Requester
        def initialize(host, port)
          @host = host
          @port = port
        end

        def process_request(request)
          socket = get_connection(@host, @port)
          write_request(socket, request)
          response_obj = Msf::Aggregator::Http::Responder.get_data(socket, true)
          close_connection(socket)
          response_obj
        end

        def write_request(connection, request)
          request.headers.each do |header|
            connection.write(header)
          end
          connection.write(request.body) unless request.body.nil?
        end

        def get_connection(host, port)
          TCPSocket.new host, port
        end

        def close_connection(connection)
          connection.close
        end

      end
    end
  end
end