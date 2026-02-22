# frozen_string_literal: true

require_relative 'helper'
require 'uma/http'
require 'uma/server'
require 'rack/lint'

class HTTPTest < UMBaseTest

  HTTP = Uma::HTTP

  def setup
    super
    @s1, @s2 = UM.socketpair(UM::AF_UNIX, UM::SOCK_STREAM, 0)
  end

  def teardown
    machine.close(@s1) rescue nil
    machine.close(@s2) rescue nil
  end

  def test_request_response_cycle
    config = {
      app: ->(env) { [200, {}, 'Hello world!'] }
    }

    f = machine.spin do
      HTTP.http_connection(machine, config, @s2)
    end

    request = "GET / HTTP/1.1\r\n\r\n"
    machine.send(@s1, request, request.bytesize, 0)

    buf = +''
    machine.recv(@s1, buf, 256, 0)

    assert_equal "HTTP/1.1 200\r\ntransfer-encoding: chunked\r\n\r\nc\r\nHello world!\r\n0\r\n\r\n", buf
  ensure
    if f && !f.done?
      machine.schedule(f, UM::Terminate.new)
      machine.join(f)
    end
  end

  def test_should_process_next_request?
    skip "Not yet implemented"
  end

  def test_format_headers
    h = HTTP.format_headers({})
    assert_equal "\r\n", h

    h = HTTP.format_headers({
      'foo' => 'bar'
    })
    assert_equal "foo: bar\r\n\r\n", h

    h = HTTP.format_headers({
      'foo' => 'bar',
      'bar' => 'baz'
    })
    assert_equal "foo: bar\r\nbar: baz\r\n\r\n", h

    h = HTTP.format_headers({
      'foo' => 'bar',
      'bar' => ['baz', 'bazz', 'bazzz']
    })
    assert_equal "foo: bar\r\nbar: baz\r\nbar: bazz\r\nbar: bazzz\r\n\r\n", h

    assert_raises(HTTP::ResponseError) {
      HTTP.format_headers({
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

    assert_equal "HTTP/1.1 200\r\nfoo: bar\r\ntransfer-encoding: chunked\r\n\r\n5\r\nHello\r\n0\r\n\r\n", buf
  end

  def test_send_rack_response_array
    env = {}
    resp = [200, { 'foo' => 'bar' }, ['Foo', 'baRbaZ']]
    HTTP.send_rack_response(machine, env, @s2, resp)

    buf = +''
    machine.recv(@s1, buf, 256, 0)

    assert_equal "HTTP/1.1 200\r\nfoo: bar\r\ntransfer-encoding: chunked\r\n\r\n3\r\nFoo\r\n6\r\nbaRbaZ\r\n0\r\n\r\n", buf
  end

  def test_send_rack_response_array
    env = {}
    resp = [200, { 'foo' => 'bar' }, ['Foo', 'baRbaZ']]
    HTTP.send_rack_response(machine, env, @s2, resp)

    buf = +''
    machine.recv(@s1, buf, 256, 0)

    assert_equal "HTTP/1.1 200\r\nfoo: bar\r\ntransfer-encoding: chunked\r\n\r\n3\r\nFoo\r\n6\r\nbaRbaZ\r\n0\r\n\r\n", buf
  end

  def test_send_rack_response_enumerable
    env = {}
    set = Set.new
    set << 'abc' << 'defg'
    resp = [200, { 'foo' => 'bar' }, set]
    HTTP.send_rack_response(machine, env, @s2, resp)

    buf = +''
    machine.recv(@s1, buf, 256, 0)

    assert_equal "HTTP/1.1 200\r\nfoo: bar\r\ntransfer-encoding: chunked\r\n\r\n3\r\nabc\r\n4\r\ndefg\r\n0\r\n\r\n", buf
  end

  def test_send_rack_response_callable
    env = {}
    resp = [200, { 'foo' => 'bar' }, ->(stream) do
      stream << 'hiho'
      stream << 'encyclopaedia'
    end]
    # read_stream = UM::Stream.new(machine, @s1)
    HTTP.send_rack_response(machine, env, @s2, resp)
    machine.close(@s2)

    buf = +''
    machine.recv(@s1, buf, 128, 0)
    assert_equal "HTTP/1.1 200\r\nfoo: bar\r\ntransfer-encoding: chunked\r\n\r\n4\r\nhiho\r\nd\r\nencyclopaedia\r\n0\r\n\r\n", buf
  end

  def test_parse_header
    e = Uma::HTTP::ParseError
    assert_raises(e) { HTTP.parse_header({}, 'foo')}
    assert_raises(e) { HTTP.parse_header({}, 'foo:')}

    HTTP.parse_header((env = {}), 'fOo: bAr')
    assert_equal({ 'HTTP_FOO' => 'bAr' }, env)

    HTTP.parse_header((env = {}), 'content-length: 80')
    assert_equal({ 'CONTENT_LENGTH' => '80' }, env)

    HTTP.parse_header((env = {}), 'Content-length: 80')
    assert_equal({ 'CONTENT_LENGTH' => '80' }, env)

    HTTP.parse_header((env = {}), 'Content-type: foo')
    assert_equal({ 'CONTENT_TYPE' => 'foo' }, env)

    HTTP.parse_header((env = {}), 'Accept: bar')
    assert_equal({ 'HTTP_ACCEPT' => 'bar' }, env)

    HTTP.parse_header((env = {}), 'host: foo.bar')
    assert_equal({
      'HTTP_HOST' => 'foo.bar',
      'SERVER_NAME' => 'foo.bar'
    }, env)
  end

  def test_parse_request_line
    e = Uma::HTTP::ParseError
    assert_raises(e) { HTTP.parse_header({}, '')}
    assert_raises(e) { HTTP.parse_header({}, 'foo')}
    assert_raises(e) { HTTP.parse_header({}, 'GET /tr')}
    assert_raises(e) { HTTP.parse_header({}, 'GET HTTP')}

    HTTP.parse_request_line((env = {}), 'geT /foo HTTP/1.1')
    assert_equal({
      'REQUEST_METHOD' => 'get',
      'PATH_INFO' => '/foo',
      'QUERY_STRING' => '',
      'SERVER_PROTOCOL' => 'HTTP/1.1'
    }, env)

    HTTP.parse_request_line((env = {}), 'geT /foo?q=3&r=4 HTTP/1.1')
    assert_equal({
      'REQUEST_METHOD' => 'get',
      'PATH_INFO' => '/foo',
      'QUERY_STRING' => 'q=3&r=4',
      'SERVER_PROTOCOL' => 'HTTP/1.1'
    }, env)
  end

  def test_get_request_env
    config = Uma::ServerControl.server_config({})
    stream = UM::Stream.new(machine, @s2)

    machine.sendv(@s1, "GET /a HTTP/1.1\r\n\r\n")
    env = HTTP.get_request_env(config, stream)
    assert_kind_of Hash, env
    assert_equal 'http', env['rack.url_scheme']
    assert_equal true, env['rack.hijack?']
    assert_kind_of Proc, env['rack.hijack']
    assert_equal 'get', env['REQUEST_METHOD']
    assert_equal '/a', env['PATH_INFO']
    assert_equal '', env['QUERY_STRING']
    assert_equal 'HTTP/1.1', env['SERVER_PROTOCOL']
  end

  class MockErrorStream
    def initialize(&block)
      @write_block = block
    end

    def puts(s)
      write("#{s}\n")
    end

    def write(s)
      @write_block.(s)
    end

    def flush = self
    def close = self
  end

  def make_http_request(app, req, send_resp = true)
    fd1, fd2 = UM.socketpair(UM::AF_UNIX, UM::SOCK_STREAM, 0)

    config = Uma::ServerControl.server_config({
      error_stream: MockErrorStream.new { |w| STDERR << w }
    })

    machine.sendv(fd1, req)
    machine.shutdown(fd1, UM::SHUT_WR)
    stream = UM::Stream.new(machine, fd2)
    env = HTTP.get_request_env(config, stream)

    return if !send_resp

    response = app.(env)
    if !env['uma.hijacked?']
      HTTP.send_rack_response(machine, env, fd2, response)
    end

    buf = +''
    machine.recv(fd1, buf, 256, 0)
    buf
  ensure
    machine.close(fd1)
    machine.close(fd2) rescue nil
  end

  def req_resp_lint(app, req, expected_resp)
    lint_app = Rack::Lint.new(app)
    make_http_request(lint_app, req, false)

    resp = make_http_request(app, req)
    assert_equal expected_resp, resp
  end

  def test_get_basic
    req_resp_lint(
      ->(env) { [200, {}, 'Hello'] },
      "GET / HTTP/1.1\r\n\r\n",
      "HTTP/1.1 200\r\ntransfer-encoding: chunked\r\n\r\n5\r\nHello\r\n0\r\n\r\n"
    )

    req_resp_lint(
      ->(env) { [404, {}, ''] },
      "GET / HTTP/1.1\r\n\r\n",
      "HTTP/1.1 404\r\ncontent-length: 0\r\n\r\n"
    )
  end

  def test_post_with_body_chunked
    chunks = []
    req_resp_lint(
      ->(env) {
        env['rack.input'].each { chunks << it }
        [200, {}, chunks]
      },
      "POST /foo HTTP/1.1\r\ntransfer-encoding: chunked\r\n\r\nb\r\nwowie-zowie\r\n3\r\nwow\r\n0\r\n\r\n",
      "HTTP/1.1 200\r\ntransfer-encoding: chunked\r\n\r\nb\r\nwowie-zowie\r\n3\r\nwow\r\n0\r\n\r\n"
    )
  end

  def test_post_with_body_unchunked
    chunks = []
    req_resp_lint(
      ->(env) {
        env['rack.input'].each { chunks << it }
        [200, {}, chunks]
      },
      "POST /foo HTTP/1.1\r\ncontent-length: 11\r\n\r\nwowie-zowie",
      "HTTP/1.1 200\r\ntransfer-encoding: chunked\r\n\r\nb\r\nwowie-zowie\r\n0\r\n\r\n"
    )
  end

  def test_full_hijack
    req_resp_lint(
      ->(env) {
        if env['rack.hijack?']
          io = env['rack.hijack'].()
          io.puts 'foo1'
          msg = io.read(50)
          io << "You said: #{msg}"
          io.close
        else
          [500, {}, "No hijack"]
        end
      },
      "GET / HTTP/1.1\r\n\r\nblahBlah",
      "foo1\nYou said: blahBlah"
    )
  end

  def test_partial_hijack
    req_resp_lint(
      ->(env) {
        if env['rack.hijack?']
          [
            200,
            {
              'Foo' => 'barbaz',
              'rack.hijack' => ->(io) {
                io.puts 'bouyakasha'
                io.close
              }
            },
            '']
        else
          [500, {}, "No hijack"]
        end
      },
      "GET / HTTP/1.1\r\n\r\n",
      "HTTP/1.1 200\r\nFoo: barbaz\r\n\r\nbouyakasha\n"
    )
  end
end
