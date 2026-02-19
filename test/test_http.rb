# frozen_string_literal: true

require_relative 'helper'
require 'uma/http'

class HTTPTest < UMBaseTest

  HTTP = Uma::HTTP

  def setup
    super
    @s1, @s2 = UM.socketpair(UM::AF_UNIX, UM::SOCK_STREAM, 0)
  end

  def test_request_response_cycle
    config = {
      app: ->(env) { [200, {}, 'Hello world!'] }
    }

    f = machine.spin do
      HTTP.http_connection(machine, config, @s2)
    rescue => e
      p e
      p e.backtrace
      exit!
    end

    request = "GET / HTTP/1.1\r\n\r\n"
    machine.send(@s1, request, request.bytesize, 0)

    buf = +''
    machine.recv(@s1, buf, 256, 0)

    assert_equal "HTTP/1.1 200\r\n\r\nHello world!", buf
  ensure
    if f && !f.done?
      machine.schedule(f, UM::Terminate.new)
      machine.join(f)
    end
  end

  def test_should_process_next_request?
    skip "Not yet implemented"
  end

  def test_format_response_headers
    h = HTTP.format_response_headers({})
    assert_equal "\r\n", h

    h = HTTP.format_response_headers({
      'foo' => 'bar'
    })
    assert_equal "foo: bar\r\n\r\n", h

    h = HTTP.format_response_headers({
      'foo' => 'bar',
      'bar' => 'baz'
    })
    assert_equal "foo: bar\r\nbar: baz\r\n\r\n", h

    h = HTTP.format_response_headers({
      'foo' => 'bar',
      'bar' => ['baz', 'bazz', 'bazzz']
    })
    assert_equal "foo: bar\r\nbar: baz\r\nbar: bazz\r\nbar: bazzz\r\n\r\n", h

    assert_raises(HTTP::ResponseError) {
      HTTP.format_response_headers({
        'foo' => 'bar',
        'bar' => 123
      })
    }
  end

  def test_send_rack_response
    env = {}
    resp = [200, { 'foo' => 'bar' }, 'Hello']
    HTTP.send_rack_response(machine, env, @s2, resp)

    buf = +''
    machine.recv(@s1, buf, 256, 0)

    assert_equal "HTTP/1.1 200\r\nfoo: bar\r\n\r\nHello", buf
  end
end
