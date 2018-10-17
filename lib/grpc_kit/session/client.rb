# frozen_string_literal: true

require 'forwardable'
require 'ds9'
require 'grpc_kit/session/stream'

module GrpcKit
  module Session
    class Client < DS9::Client
      extend Forwardable

      delegate %i[send_event recv_event] => :@io

      # @params io [GrpcKit::Session::IO]
      def initialize(io, handler, opts = {})
        super() # initialize DS9::Session

        @io = io
        @streams = {}
        @handler = handler
        @opts = opts
      end

      def start_request(data, headers)
        stream_id = submit_request(headers, data)
        stream = GrpcKit::Session::Stream.new(stream_id: stream_id, send_data: data)
        stream.stream_id = stream_id
        @streams[stream_id] = stream
        stream
      end

      def start(stream_id)
        stream = @streams.fetch(stream_id)

        loop do
          if (!want_read? && !want_write?) || stream.end_stream?
            break
          end

          run_once
        end
      end

      def run_once
        return if @stop

        if want_read?
          do_read
        end

        if want_write?
          send
        end
      end

      private

      def do_read
        receive
      rescue IOError => e
        finish
        raise e
      rescue DS9::Exception => e
        finish
        if DS9::ERR_EOF == e.code
          @peer_shutdowned = true
          return
          # raise EOFError
        end

        raise e
      end

      # nghttp2_session_callbacks_set_on_frame_send_callback
      def on_frame_recv(frame)
        GrpcKit.logger.debug("on_frame_recv #{frame}")
        case frame
        when DS9::Frames::Data
          stream = @streams[frame.stream_id]

          if frame.end_stream?
            stream.remote_end_stream = true
          end

          unless stream.inflight
            stream.inflight = true
          end

        when DS9::Frames::Headers
          stream = @streams[frame.stream_id]

          if frame.end_stream?
            stream.remote_end_stream = true
          end

          # when DS9::Frames::Goaway
          # when DS9::Frames::RstStream
        end

        true
      end

      # nghttp2_session_callbacks_set_on_frame_send_callback
      def on_frame_send(frame)
        GrpcKit.logger.debug("on_frame_send #{frame}")
        case frame
        when DS9::Frames::Data, DS9::Frames::Headers
          stream = @streams[frame.stream_id]
          if frame.end_stream?
            stream.local_end_stream = true
          end
        end

        true
      end

      # nghttp2_session_callbacks_set_on_stream_close_callback
      def on_stream_close(stream_id, error_code)
        GrpcKit.logger.debug("on_stream_close stream_id=#{stream_id}, error_code=#{error_code}")
        stream = @streams.delete(stream_id)
        return unless stream

        stream.end_stream
      end

      # nghttp2_session_callbacks_set_on_data_chunk_recv_callback
      def on_data_chunk_recv(stream_id, data, _flags)
        stream = @streams[stream_id]
        if stream
          stream.pending_recv_data.write(data)
        end
      end

      # # for nghttp2_session_callbacks_set_on_frame_not_send_callback
      # def on_frame_not_send(frame, reason)
      # end

      # # for nghttp2_session_callbacks_set_on_header_callback
      # def on_header(name, value, frame, flags)
      # end

      # # for nghttp2_session_callbacks_set_on_begin_headers_callback
      # def on_begin_header(name, value, frame, flags)
      # end

      # # for nghttp2_session_callbacks_set_on_begin_frame_callback
      # def on_begin_frame(frame_header)
      # end

      # # for nghttp2_session_callbacks_set_on_invalid_frame_recv_callback
      # def on_invalid_frame_recv(frame, error_code)
      # end
    end
  end
end
