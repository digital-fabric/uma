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
        send_error_response(machine, fd, e)
      end
    end

    def get_request_env(config, stream)
      env = {
        'rack.url_scheme' => 'http',
        'SCRIPT_NAME' => '',
        'SERVER_NAME' => 'localhost',
        'rack.errors' => config[:error_stream]
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

    def send_rack_response(machine, env, fd, response)
      status, headers, body = response

      case body
      when nil, ''
        headers['content-length'] = 0
      else
        headers['content-length'] = body.size.to_s
      end

      buf1 = "HTTP/1.1 #{status}\r\n"
      buf2 = format_headers(headers)
      
      if body
        machine.sendv(fd, buf1, buf2, body)
      else
        machine.sendv(fd, buf1, buf2)
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
