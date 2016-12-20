require "msf/aggregator/http/request"
require "msf/aggregator/http/responder"

module Msf
  module Aggregator
    module Http
      class SslResponder < Responder
        def initialize(uri)
          super
        end

        def getConnection(host, port)
          ssl_client = nil
          begin
            tcp_client = TCPSocket.new host, port
            ssl_context = OpenSSL::SSL::SSLContext.new
            ssl_context.ssl_version = :TLSv1
            ssl_client = OpenSSL::SSL::SSLSocket.new tcp_client, ssl_context
            ssl_client.connect
          rescue StandardError => e
            log 'error on console connect ' + e.to_s
            send_parked_response(connection)
          end
          ssl_client
        end

        def close_connection(connection)
          connection.sync_close = true
          connection.close
        end
      end
    end
  end
end