require 'openssl'
require 'socket'

require 'msf/aggregator/logger'
require 'msf/aggregator/https_forwarder'

module Msf
  module Aggregator

    class ConnectionManager
      attr_reader :listening_servers

      def initialize
        @listening_ports = []
        @listening_threads = []
        @listening_servers = []
        @parked_hosts = []
        @forwarders = []
      end

      def self.ssl_generate_certificate
        yr   = 24*3600*365
        vf   = Time.at(Time.now.to_i - rand(yr * 3) - yr)
        vt   = Time.at(vf.to_i + (10 * yr))
        cn   = 'localhost'
        key  = OpenSSL::PKey::RSA.new(2048){ }
        cert = OpenSSL::X509::Certificate.new
        cert.version    = 2
        cert.serial     = (rand(0xFFFFFFFF) << 32) + rand(0xFFFFFFFF)
        cert.subject    = OpenSSL::X509::Name.new([["CN", cn]])
        cert.issuer     = OpenSSL::X509::Name.new([["CN", cn]])
        cert.not_before = vf
        cert.not_after  = vt
        cert.public_key = key.public_key

        ef = OpenSSL::X509::ExtensionFactory.new(nil,cert)
        cert.extensions = [
            ef.create_extension("basicConstraints","CA:FALSE")
        ]
        ef.issuer_certificate = cert

        cert.sign(key, OpenSSL::Digest::SHA256.new)

        [key, cert, nil]
      end

      def ssl_parse_certificate(certificate)
        unless certificate.nil?
          # parse the cert
          Logger.log("not implemented")
        end
      end

      # def create_admin_listener(host, port)
      #   admin = Thread.new {
      #     begin
      #       @listening_ports << port
      #       listeningPort = port
      #
      #       server = TCPServer.new(host, listeningPort)
      #       @listening_servers << server
      #       sslContext = OpenSSL::SSL::SSLContext.new
      #       sslContext.key, sslContext.cert = Msf::Aggregator::ConnectionManager.ssl_generate_certificate
      #       sslServer = OpenSSL::SSL::SSLServer.new(server, sslContext)
      #
      #       Logger.log "Listening on port #{host}:#{listeningPort}"
      #
      #       loop do
      #         connection = sslServer.accept
      #         Thread.new do
      #           begin
      #             # register console request path
      #             input = MessagePack::Unpacker.new(connection)
      #             input.each do |obj|
      #               process_request(obj)
      #             end
      #           rescue
      #             Logger.log $!
      #           end
      #         }
      #
      #         Thread.new {
      #           begin
      #             # register console response path
      #             @output = MessagePack::Packer.new(connection)
      #           rescue
      #             Logger.log $!
      #           end
      #         }
      #
      #       end
      #     end
      #
      #     def process_request(data)
      #       # This processor relies on the expectation that all data objects extend Type Msf::Aggregator::Message
      #       # starting with getting session list from the aggregator
      #       sessions = Msf::Aggregator::Admin::Sessions.new(@listening_servers, data.id)
      #
      #       @output.write(sessions)
      #
      #       # assume data is a request for a new default listener for now
      #       # NOTE: this currently uses message to define forward source, may be important to validate
      #       # the forward address is owned by the original command client channel console before registering
      #       # forwarder = Metasploit::Aggregator::MessageForwarder.new(data.lhost, data.lport, data.uri)
      #       # proxy_handlers.create_https_listener(data.host, data.port, forwarder)
      #     end
      #
      #     private :process_request
      #   end
      #   @listening_threads << admin
      #   admin
      # end

      def create_https_listener(host, port, certificate)
        forwarder = Msf::Aggregator::HttpsForwarder.new
        forwarder.log_messages = true
        handler = Thread.new do
          begin
            @listening_ports << port
            listening_port = port

            server = TCPServer.new(host, listening_port)
            @listening_servers << server
            ssl_context = OpenSSL::SSL::SSLContext.new
            # ssl_context.key, ssl_context.cert = parse_certificate(certificate)
            # if certificate.nil?
              ssl_context.key, ssl_context.cert = Msf::Aggregator::ConnectionManager.ssl_generate_certificate
            # end
            ssl_server = OpenSSL::SSL::SSLServer.new(server, ssl_context)

            Logger.log "Listening on port #{host}:#{listening_port}"

            loop do
              Logger.log "waiting for connection on #{host}:#{port}"
              connection = ssl_server.accept
              Logger.log "got connection on #{host}:#{port}"
              Thread.new {
                begin
                  if @parked_hosts.include? connection.io.peeraddr[3]
                    forwarder.send_parked_response(connection)
                    break
                  end
                  forwarder.forward(connection)
                rescue
                  Logger.log $!
                end
                Logger.log "completed connection on #{host}:#{port}"
              }
            end
          end
        end
        @listening_threads << handler
        @forwarders << forwarder
        handler
      end

      def register_forward(rhost, rport, payload_list)
        if payload_list.nil?
          @forwarders.each do |forwarder|
              forwarder.add_route(rhost, rport, nil)
          end
        else
        # TODO: consider refactoring the routing into a routing service loaded into all forwarding classes
          unless @forwarders.nil?
            @forwarders.each do |forwarder|
              payload_list.each do |payload|
                forwarder.add_route(rhost, rport, payload)
              end
            end
          end
        end
      end

      def connections
        connections = {}
        @forwarders.each do |forwarder|
          connections = connections.merge forwarder.connections
        end
        connections
      end

      def stop
        @listening_threads.each do |thread|
          thread.exit
        end
        @listening_servers.each do |server|
          server.close
        end
      end

      def park(host)
        # all listeners refer to a global parking list for now
        @parked_hosts << host
        @forwarders.each do |forwarder|
          forwarder.add_route(nil, nil, host)
        end
        Logger.log "parking #{host}"
      end

      private :ssl_parse_certificate
    end
  end
end
