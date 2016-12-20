require 'socket'
require 'msf/aggregator/forwarder'
require 'msf/aggregator/http/request'
require 'msf/aggregator/http/responder'
require 'msf/aggregator/logger'
require 'msf/aggregator/router'

module Msf
  module Aggregator
    class HttpForwarder < Forwarder
      CONNECTION_TIMEOUT = 60 # one minute

      attr_accessor :log_messages
      attr_reader :response_queues

      def initialize
        super
      end

      def forward(connection)
        #forward input requests
        request_obj = Msf::Aggregator::Http::Responder.get_data(connection, false)
        uri = Msf::Aggregator::Http::Request.parse_uri(request_obj)
        @forwarder_mutex.synchronize do
          unless uri.nil?
            unless @response_queues[uri]
              uri_responder = Msf::Aggregator::Http::Responder.new(uri)
              uri_responder.log_messages = @log_messages
              @response_queues[uri] = uri_responder
            end
            @response_queues[uri].queue << request_obj
            @response_queues[uri].time = Time.now
          else
            connection.close
          end
        end
      end
    end
  end
end
