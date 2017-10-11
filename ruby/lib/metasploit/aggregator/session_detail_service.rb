require 'digest/md5'
require 'singleton'
require 'metasploit/aggregator/logger'
require 'metasploit/aggregator/tlv/packet'
require 'metasploit/aggregator/tlv/uuid'

module Metasploit
  module Aggregator
    class SessionDetailService
      include Singleton

      def initialize
        @mutex = Mutex.new
        @tlv_queue = Queue.new
        @thread = create_processor
        @payloads_count = 0;
        @detail_cache = {}
      end

      def add_request(request, payload)
        @mutex.synchronize do
          @tlv_queue << [ request, payload ]
        end
        begin
          if @detail_cache[payload] && @detail_cache[payload]['REMOTE_SOCKET'].nil? && request.socket
            @detail_cache[payload]['REMOTE_SOCKET'] = "#{request.socket.peeraddr[3]}:#{request.socket.peeraddr[1]}"
            @detail_cache[payload]['LOCAL_SOCKET'] = "#{request.socket.addr[3]}:#{request.socket.addr[1]}"
          end
        rescue Exception
          Logger.log "error retrieving socket details"
        end
      end

      def session_details(payload)
        @detail_cache[payload]
      end

      def eval_tlv_enc(request)
        # this is really expensive as we have to process every
        # piece of information presented from the console to eval for enc requests
        response = nil
        begin
        if request.body && request.body.length > 0
          packet = Metasploit::Aggregator::Tlv::Packet.new(0)
          packet.add_raw(request.body)
          packet.from_r
          if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_METHOD)
            packet_val = packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_METHOD)
            if packet_val == "core_negotiate_tlv_encryption"
              response = Metasploit::Aggregator::Tlv::Packet.create_response(packet)
              response.add_tlv(Metasploit::Aggregator::Tlv::TLV_TYPE_RESULT, 0)
              response
            end
          end
        end
        rescue Exception
          # any exception return nil
          Logger.log "error evaluating tlv packet"
          response = nil
        end
        response
      end

      def process_tlv
        while true
          begin
            request, payload = @tlv_queue.pop
            if request.body && request.body.length > 0
              packet = Metasploit::Aggregator::Tlv::Packet.new(0)
              packet.add_raw(request.body)
              packet.from_r
              unless @detail_cache[payload]
                @detail_cache[payload] = { 'ID' => (@payloads_count += 1) }
              end
              if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_UUID)
                args = { :raw => packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_UUID) }
                @detail_cache[payload]['UUID'] = Metasploit::Aggregator::Tlv::UUID.new(args)
              end
              if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_MACHINE_ID)
                machine_id = packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_MACHINE_ID)
                @detail_cache[payload]['MachineID'] = Digest::MD5.hexdigest(machine_id.downcase.strip)
                _user, computer_name = machine_id.split(":")
                unless computer_name.nil?
                  @detail_cache[payload]['HOSTNAME'] = computer_name
                end
              end
              if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_USER_NAME)
                @detail_cache[payload]['USER'] = packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_USER_NAME)
              end
              if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_COMPUTER_NAME)
                @detail_cache[payload]['HOSTNAME'] = packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_COMPUTER_NAME)
              end
              if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_OS_NAME)
                @detail_cache[payload]['OS'] = packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_OS_NAME)
              end

              # remove sessions that get shutdown
              if packet.has_tlv?(Metasploit::Aggregator::Tlv::TLV_TYPE_METHOD)
                packet_val = packet.get_tlv_value(Metasploit::Aggregator::Tlv::TLV_TYPE_METHOD)
                if packet_val == "core_shutdown"
                  @detail_cache.delete(payload)
                end
              end
            end
          rescue Exception
            Logger.log "error processing tlv for session details"
          end
        end
      end

      def create_processor
        processor = Thread.new do
          while true # always restart the processor
            begin
              process_tlv
            rescue Exception
              Logger.log "tlv processing thread error -- restarting"
            end
          end
        end
        processor
      end

      private :create_processor
    end
  end
end