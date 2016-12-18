require 'singleton'

module Msf
  module Aggregator
    class Router
      include Singleton

      def initialize
        @mutex = Mutex.new
        @forward_routes = {}
      end

      def add_route(rhost, rport, payload)
        forward = [rhost, rport]
        @mutex.synchronize do
          if payload.nil?
            @forward_routes['default'] = forward
            return
          end
          @forward_routes[payload] = forward
        end
      end

      def remove_route(payload)
        unless payload.nil?
          @mutex.synchronize do
            @forward_routes.delete(payload)
          end
        end
      end

      def get_forward(uri)
        unless @forward_routes[uri].nil?
          @forward_routes[uri]
        else
          @forward_routes['default']
        end
      end
    end
  end
end