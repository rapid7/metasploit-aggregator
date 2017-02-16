require 'socket'
require 'openssl'
require 'thread'
require 'msgpack'
require 'msgpack/rpc'
require 'securerandom'

require 'metasploit/aggregator/version'
require 'metasploit/aggregator/cable'
require 'metasploit/aggregator/connection_manager'
require 'metasploit/aggregator/https_forwarder'
require 'metasploit/aggregator/http'
require 'metasploit/aggregator/logger'

module Metasploit
  module Aggregator

    class Service
      # return availability status of the service
      def available?
        # index for impl
      end

      # returns map of sessions available from the service
      def sessions
        # index for impl
      end

      def cables
        # index for impl
      end

      # sets forwarding for a specific session to promote
      # that session for local use, obtained sessions are
      # not reported in getSessions
      def obtain_session(payload, uuid)
        # index for impl
      end

      # parks a session and makes it available in the getSessions
      def release_session(payload)
        # index for impl
      end

      # return any extended details for the payload requested
      def session_details(payload)

      end

      # start a listening port maintained on the service
      # connections are forwarded to any registered default
      # TODO: may want to require a type here for future proof of api
      def add_cable(type, host, port, certificate = nil)
        # index for impl
      end

      def remove_cable(host, port)
        # index for impl
      end

      def register_default(uuid, payload_list)
        # index for impl
      end

      def default
        # index for impl
      end

      # returns list of IP addressed available to the service
      # TODO: consider also reporting "used" ports (may not be needed)
      def available_addresses
        # index for impl
      end

      # register the object to pass request from cables to
      def register_response_channel(requester)

      end
    end

    class ServerProxy < Service
      attr_reader :uuid
      @host = @port = @socket = nil
      @response_queue = []

      def initialize(host, port)
        @host = host
        @port = port
        @client = MessagePack::RPC::Client.new(@host, @port)
        @uuid = SecureRandom.uuid
      end

      def available?
        @client.call(:available?)
      rescue MessagePack::RPC::ConnectionTimeoutError => e
        false
      end

      def sessions
        @client.call(:sessions)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def cables
        @client.call(:cables)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end


      def obtain_session(payload, uuid)
        @client.call(:obtain_session, payload, uuid)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def release_session(payload)
        @client.call(:release_session, payload)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def session_details(payload)
        @client.call(:session_details, payload)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def add_cable(type, host, port, certificate = nil)
        @client.call(:add_cable, type, host, port, certificate)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def remove_cable(host, port)
        @client.call(:remove_cable, host, port)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def register_default(uuid, payload_list)
        @client.call(:register_default, uuid, payload_list)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def default
        @client.call(:default)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def available_addresses
        @client.call(:available_addresses)
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def stop
        @client.close
        @client = nil
        @listening_thread.join if @listening_thread
      end

      def register_response_channel(requester)
        unless requester.kind_of? Metasploit::Aggregator::Http::Requester
          raise ArgumentError("response channel class invalid")
        end
        @response_io = requester
        start_responding
      end

      def start_responding
        @listening_thread = Thread.new do
          @listener_client = MessagePack::RPC::Client.new(@host, @port) unless @listener_client
          while @client
            begin
              sleep 0.1 # polling for now need
              result, result_obj, session_id, response_obj = nil
              result = @listener_client.call(:request, @uuid)
              next unless result # just continue to poll if no request is found
              result_obj = Metasploit::Aggregator::Http::Request.from_msgpack(result)
              session_id = Metasploit::Aggregator::Http::Request.parse_uri(result_obj)
              response_obj = @response_io.process_request(result_obj)
              @listener_client.call(:respond, session_id, response_obj.to_msgpack)
            rescue MessagePack::RPC::TimeoutError
              next
            rescue
              Logger.log $!
            end
          end
          @listener_client.close
        end
      end
    end # ServerProxy

    class Server < Service
      # include Metasploit::Aggregator::ConnectionManager

      def initialize
        @manager = nil
        @router = Router.instance
      end

      def start
        @manager = Metasploit::Aggregator::ConnectionManager.new
        true
      end

      def available?
        !@manager.nil?
      end

      def sessions
        @manager.connections
      end

      def cables
        @manager.cables
      end

      def obtain_session(payload, uuid)
        # return session object details or UUID/uri
        # forwarding will cause new session creation on the console
        # TODO: check and set lock on payload requested see note below in register_default
        @manager.register_forward(uuid, [ payload ])
        true # update later to return if lock obtained
      end

      def release_session(payload)
        @manager.park(payload)
        true # return always return success for now
      end

      def session_details(payload)
        @manager.connection_details(payload)
      end

      def add_cable(type, host, port, certificate = nil)
        unless @manager.nil?
          case type
            when Cable::HTTPS
              # TODO: check if already listening on that port
              @manager.add_cable_https(host, port, certificate)
            when Cable::HTTP
              @manager.add_cable_http(host, port)
            else
              Logger.log("#{type} cables are not supported.")
          end
        end
        true
      end

      def remove_cable(host, port)
        unless @manager.nil?
          @manager.remove_cable(host, port)
        end
      end

      def register_default(uuid, payload_list)
        # add this payload list to each forwarder for this remote console
        # TODO: consider adding boolean param to ConnectionManager.register_forward to 'lock'
        @manager.register_forward(uuid, payload_list)
        true
      end

      def default
        send, recv, console = @router.get_forward('default')
        console
      end

      def available_addresses
        addr_list = Socket.ip_address_list
        addresses = []
        addr_list.each do |addr|
          addresses << addr.ip_address
        end
        addresses
      end

      def stop
        unless @manager.nil?
          @manager.stop
        end
        @manager = nil
        true
      end

      def request(uuid)
        # return requests here
        result = nil
        send, recv = @router.reverse_route(uuid)
        if send.length > 0
          result = send.pop
        end
        result
      end

      def respond(uuid, data)
        send, recv = @router.get_forward(uuid)
        recv << data unless recv.nil?
        true
      end

      def register_response_channel(io)
        # not implemented "client only method"
        response = "register_response_channel not implemented on server"
        Logger.log response
        response
      end
    end # class Server

    # wrapping class required to avoid MsgPack specific needs to parallel request processing.
    class AsyncMsgPackServer < Server

      def initialize
        super
      end

      # MsgPack specific wrapper for listener due to lack of parallel processing
      def request(uuid)
        result = super(uuid)
        sendMsg = nil
        if result
          begin
            sendMsg = result.to_msgpack
          rescue Exception => e
            Logger.log e.backtrace
            # when an error occurs here we should likely respond with an error of some sort to remove block on response
          end
        end
        sendMsg
      end

      # MsgPack specific wrapper for listener due to lack of parallel processing
      def respond(uuid, data)
        begin
          result = super(uuid, Metasploit::Aggregator::Http::Request.from_msgpack(data))
          result
        rescue Exception => e
          Logger.log e.backtrace
        end
      end
    end # AsyncMsgPackServer

    class MsgPackServer

      def initialize(host, port)
        @host = host
        @port = port

        # server = TCPServer.new(@host, @port)
        # sslContext = OpenSSL::SSL::SSLContext.new
        # sslContext.key, sslContext.cert = Metasploit::Aggregator::ConnectionManager.ssl_generate_certificate
        # sslServer = OpenSSL::SSL::SSLServer.new(server, sslContext)
        #
        @svr = MessagePack::RPC::Server.new # need to initialize this as ssl server
        # @svr.listen(sslServer, Server.new)
        @svr.listen(@host, @port, AsyncMsgPackServer.new)

        Thread.new { @svr.run }
      end

      def start
        c = MessagePack::RPC::Client.new(@host,@port)
        c.call(:start)
        c.close
      rescue MessagePack::RPC::TimeoutError => e
        Logger.log(e.to_s)
      end

      def stop
        c = MessagePack::RPC::Client.new(@host,@port)
        c.call(:stop)
        c.close
        @svr.close
      end
    end
  end
end
