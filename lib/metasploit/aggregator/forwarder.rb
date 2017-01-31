module Metasploit
  module Aggregator
    class Forwarder
      CONNECTION_TIMEOUT = 60 # one minute

      attr_accessor :log_messages
      attr_reader :response_queues

      def initialize
        @log_messages = false
        @response_queues = {}
        @forwarder_mutex = Mutex.new
        @router = Router.instance
      end

      # stub for indexing
      def forward(connection)

      end

      def connections
        # TODO: for now before reporting connections flush stale ones
        flush_stale_sessions
        connections = {}
        @response_queues.each_pair do |connection, queue|
          forward = 'parked'
          send, recv, console = @router.get_forward(connection)
          unless console.nil?
            forward = "#{console}"
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
            stale_queue = @response_queues.delete(uri)
            stale_queue.stop_processing unless stale_queue.nil?
          end
        end
      end

      private :flush_stale_sessions
    end
  end
end