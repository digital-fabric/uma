# frozen_string_literal: true

module Uma
  module HTTP
    
    class Error < StandardError; end
    class ParseError < Error; end
    class ResponseError < Error; end

    extend self
    
    def http_connection(machine, config, fd)
      stream = UM::Stream.new(machine, fd)
      while true
        break if !process_request(machine, config, fd, stream)
      end
    end

    def process_request(machine, config, fd, stream)
      env = get_request_env(config, stream)

      rack_response = config[:app].(env)
      send_rack_response(machine, env, fd, rack_response)

      should_process_next_request?(env)
    rescue => e
      if (h = config[:error_handler])
        h.(e)
      else
        p e
        p e.backtrace
        exit!
        send_error_response(machine, fd, e)
      end
    end

    class RackInputStream
      def initialize(env, stream)
        @env = env
        @stream = stream
      end

      def gets
        @stream.get_line(nil, 0)
      end

      def read(length, buf = +'')
        @stream.get_string(buf, length)
      end

      def each(&)
        if @env['HTTP_TRANSFER_ENCODING'] == 'chunked'
          read_chunks(&)
        elsif (v = @env['HTTP_CONTENT_LENGTH'])
          len = v.to_i
          yield @stream.get_string(+'', len)
        end
      end

      def read_chunks
        buf = +''
        while true
          line = @stream.get_line(buf, 8)
          len = line.to_i(16)
          break if len == 0

          chunk = @stream.get_string(nil, len)
          yield chunk
          @stream.skip(2)
        end
      end

      def close
      end
    end

    def get_request_env(config, stream)
      env = {
        'rack.url_scheme' => 'http',
        'SCRIPT_NAME'   => '',
        'SERVER_NAME'   => 'localhost',
        'rack.hijack?'  => true,
        'rack.errors'   => config[:error_stream]
      }
      buf = +''
      ret = stream.get_line(buf, 4096)
      return if !ret

      parse_request_line(env, buf)
      while true
        ret = stream.get_line(buf, 4096)
        raise ParseError, "Unexpected EOF" if !ret
        break if buf.empty?

        parse_header(env, buf)
      end

      if env['CONTENT_LENGTH'] || env['HTTP_TRANSFER_ENCODING'] == 'chunked'
        env['rack.input'] = RackInputStream.new(env, stream)
      end
      env
    end

    RE_REQUEST_LINE = /^([a-z]+)\s+([^\s\?]+)(?:\?([^\s]+))?\s+(http\/[019\.]{1,3})/i

    def parse_request_line(env, line)
      m = line.match(RE_REQUEST_LINE)
      raise ParseError, 'Invalid request line' if !m

      env['REQUEST_METHOD']   = m[1].downcase
      env['PATH_INFO']        = m[2]
      env['QUERY_STRING']     = m[3] || ''
      env['SERVER_PROTOCOL']  = m[4]
    end

    RE_HEADER_LINE = /^([a-z0-9-]+):\s+(.+)/i

    def parse_header(env, line)
      m = line.match(RE_HEADER_LINE)
      raise ParseError, 'Invalid header' if !m

      key = "HTTP_#{m[1].upcase.tr('-', '_')}"
      value = m[2]
      case key
      when 'HTTP_CONTENT_TYPE'
        env['CONTENT_TYPE'] = value
      when 'HTTP_CONTENT_LENGTH'
        env['CONTENT_LENGTH'] = value
      when 'HTTP_HOST'
        env['SERVER_NAME'] = value
        env[key] = value
      else
        env[key] = value
      end
    end

    CHUNK_END = "\r\n0\r\n\r\n"

    def send_rack_response(machine, env, fd, response)
      status, headers, body = response

      chunked = nil
      case body
      when nil, ''
        headers['content-length'] = '0'
      end

      chunked = !headers['content-length']
      headers['transfer-encoding'] = 'chunked' if chunked

      buf_status = "HTTP/1.1 #{status}\r\n"
      buf_headers = format_headers(headers)
      
      if body
        if chunked
          send_body_chunked(machine, env, fd, buf_status, buf_headers, body)
        else
          machine.sendv(fd, buf_status, buf_headers, body)
        end
      else
        machine.sendv(fd, buf_status, buf_headers)
      end
    end

    class ChunkedStream
      def initialize(machine, fd, stream)
        @machine = machine
        @fd = fd
        @stream = stream
        @first_write = true
      end

      def read(len, buf = +'')
        stream.get_string(buf, len)
        buf
      end

      def write(*chunks)
        bufs = []
        chunks.each do
          bufs << (@first_write ? "#{it.bytesize.to_s(16)}\r\n" : "\r\n#{it.bytesize.to_s(16)}\r\n")
          bufs << it
          @first_write = false
        end
        @machine.sendv(@fd, *bufs)
      end
      alias_method :<<, :write

      def flush
      end

      def close_read
        @machine.shutdown(@fd, UM::SHUT_RD)
      end

      def close_write
        @machine.shutdown(@fd, UM::SHUT_WR)
      end

      def close
        return if @closed

        @closed = true
        chunked_ending = @first_write ? "0\r\n\r\n" : "\r\n0\r\n\r\n"
        @machine.sendv(@fd, chunked_ending)
      end

      def closed?
        @closed
      end
    end

    def send_body_chunked(machine, env, fd, buf_status, buf_headers, body)
      case body
      when String
        buf_chunk_header = "#{body.bytesize.to_s(16)}\r\n"
        machine.sendv(
          fd,
          buf_status,
          buf_headers,
          buf_chunk_header,
          body,
          CHUNK_END
        )
      when Array
        bufs = [buf_status, buf_headers]
        first = true
        body.each {
          bufs << (first ? "#{it.bytesize.to_s(16)}\r\n" : "\r\n#{it.bytesize.to_s(16)}\r\n")
          first = false
          bufs << it
        }
        bufs << CHUNK_END
        machine.sendv(fd, *bufs)
      else
        if body.respond_to?(:each)
          first = true
          body.each do
            chunk_header = first ? "#{it.bytesize.to_s(16)}\r\n" : "\r\n#{it.bytesize.to_s(16)}\r\n"
            if first
              machine.sendv(fd, buf_status, buf_headers, chunk_header, it)
              first = false
            else
              machine.sendv(fd, chunk_header, it)
            end
          end
          machine.sendv(fd, first ? "0\r\n\r\n" : "\r\n0\r\n\r\n")
        elsif body.respond_to?(:call)
          machine.sendv(fd, buf_status, buf_headers)
          chunked_stream = ChunkedStream.new(machine, fd, env['uma.stream'])
          body.call(chunked_stream)
        else
          raise ResponseError, "Invalid response body: #{body.inspect}"
        end
        
        chunked_stream.close if chunked_stream
        body.close if body.respond_to?(:close)
      end
    end

    def format_headers(headers)
      buf = +''
      headers.each do |k, v|
        next if k =~ /^rack\./

        case v
        when String
          buf << "#{k}: #{v}\r\n"
        when Array
          v.each { buf << "#{k}: #{it}\r\n" }
        else
          raise ResponseError, "Invalid header value #{v.inspect}"
        end
      end
      buf << "\r\n"
      buf
    end

    def should_process_next_request?(env)
      # TODO: look at env
      true
    end
  end
end
