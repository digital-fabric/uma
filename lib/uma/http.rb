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
        break if !handle_request(machine, config, fd, stream)
      end
    end

    def handle_request(machine, config, fd, stream)
      env = {
        'rack.url_scheme' => 'http',

      }
      buf = +''
      ret = stream.get_line(buf, 4096)
      return if !ret

      parse_request_line(config, env, buf)
      while true
        ret = stream.get_line(buf, 4096)
        raise ParseError, "Unexpected EOF" if !ret
        break if buf.empty?

        parse_header(env, buf)
      end

      # env[:body_reader] = ->() { read_body(stream) }

      rack_response = config[:app].(env)
      send_rack_response(machine, env, fd, rack_response)

      should_process_next_request?(env)
    rescue => e
      send_error_response(machine, fd, e)
    end

    RE_REQUEST_LINE = /^([a-z]+)\s+([^\s\?]+)(?:\?([^\s]+))?\s+(http\/[019\.]{1,3})/i

    def parse_request_line(config, env, line)
      m = line.match(RE_REQUEST_LINE)
      raise ParseError, 'Invalid request line' if !m

      env['REQUEST_METHOD']   = m[1].downcase
      env['SCRIPT_NAME']      = '/' # app's mount point, should come from config
      env['PATH_INFO']        = m[2]
      env['QUERY_STRING']     = m[3] || ''
      env['SERVER_PROTOCOL']  = m[4]
      env['SERVER_PORT']      = 80 # should come from config
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

    def send_rack_response(machine, env, fd, response)
      status, headers, body = response
      
      buf1 = "HTTP/1.1 #{status}\r\n"
      buf2 = format_response_headers(headers)
      
      machine.sendv(fd, buf1, buf2, body)
    end

    def format_response_headers(headers)
      buf = +''
      headers.each do |k, v|
        next if k =~ /^rack\./

        case v
        when String
          buf << "#{k}: #{v}\r\n"
        when Array
          v.each { buf << "#{k}: #{it}\r\n" }
        else
          raise ResponseError, 'Invalid header value'
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
