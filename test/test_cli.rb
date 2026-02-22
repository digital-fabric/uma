
# frozen_string_literal: true

require_relative 'helper'
require 'uma/cli'
require 'uma/http'
require 'uma/version'

class CLITest < UMBaseTest
  def setup
    super
    @env = {}
  end

  def read_io(io)
    io.rewind
    io.read
  end

  def cli_cmd(*argv)
    env = @env.merge(
      io_out: (@io_out = StringIO.new),
      io_err: (@io_err = StringIO.new)
    )

    argv = argv.first if argv.size == 1 && argv.first.is_a?(Array)
    CLI.(argv, env)
  end

  def cli_cmd_raise(*argv)
    env = @env.merge(
      io_out: (@io_out = StringIO.new),
      io_err: (@io_err = StringIO.new),
      error_handler: ->(e) { raise e }
    )

    argv = argv.first if argv.size == 1 && argv.first.is_a?(Array)
    CLI.(argv, env)
  end

  CLI = Uma::CLI
  E = CLI::Error

  def test_cli_no_command
    assert_raises(E::NoCommand) { cli_cmd_raise() }

    cli_cmd()
    assert_match(/│UMA│/, read_io(@io_err))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_err))
  end

  def test_cli_invalid_command
    assert_raises(E::InvalidCommand) { cli_cmd_raise('foo') }

    cli_cmd('foo')
    assert_match(/Error\: unrecognized command/, read_io(@io_err))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_err))
  end

  def test_cli_help
    cli_cmd_raise('help')
    assert_match(/│UMA│/, read_io(@io_out))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_out))
  end

  def test_cli_version
    cli_cmd_raise('version')
    assert_equal "Uma version #{Uma::VERSION}\n", read_io(@io_out)
  end

  class MockServer
    def initialize(env)
      @env = env
    end

    def start
      @env[:h][:env] = @env
    end

    def stop
    end
  end

  def test_cli_serve_mock
    @env[:h] = {}
    @env[:connection_proc] = true
    @env[:server_class] = MockServer

    cli_cmd_raise('serve')
    assert_kind_of Hash, @env[:h][:env]
  end

  def test_cli_serve_controller
    @env[:h] = {}
    @env[:norun] = true

    controller = cli_cmd_raise('serve')
    assert_kind_of Uma::CLI::Serve, controller

    server = controller.server
    assert_kind_of Uma::Server, server
  ensure
    server.stop
  end

  def socket_connect(host, port, retries = 0)
    sock = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock, '127.0.0.1', port)
    assert_equal 0, res
    sock
  rescue SystemCallError
    if retries < 10
      machine.sleep(0.05)
      socket_connect(host, port, retries + 1)
    else
      raise
    end
  end

  def make_request(host, port, req)
    sock = socket_connect(host, port)
    machine.sendv(sock, req) if req
    buf = +''
    machine.recv(sock, buf, 8192, 0)
    buf
  end

  def fork_server(*args, **opts)
    @env.merge!(opts)
    pid = fork do
      cli_cmd_raise('serve', *args)
    end
    pid
  end

  def test_cli_serve_running
    port = random_port

    pid = fork_server(
      bind: "127.0.0.1:#{port}",
      connection_proc: ->(machine, fd) {
        machine.write(fd, "foo")
      }
    )

    resp = make_request('127.0.0.1', port, nil)
    assert_equal 'foo', resp
  ensure
    machine.close(sock) rescue nil
    if pid
      Process.kill('SIGTERM', pid)
      Process.wait(pid)
    end
  end

  def test_cli_serve_with_app
    port = random_port

    pid = fork_server(
      File.join(__dir__, 'apps/simple.ru'),
      bind: "127.0.0.1:#{port}"
    )

    resp = make_request(
      '127.0.0.1', port,
      "GET /foo HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 200\r\ntransfer-encoding: chunked\r\n\r\n6\r\nsimple\r\n0\r\n\r\n", resp
  ensure
    machine.close(sock) rescue nil
    if pid
      Process.kill('SIGTERM', pid)
      Process.wait(pid)
    end
  end

  def test_cli_serve_with_default_app
    port = random_port

    pid = fork_server(
      File.join(__dir__, 'apps'),
      bind: "127.0.0.1:#{port}"
    )

    resp = make_request(
      '127.0.0.1', port,
      "GET /foo HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 200\r\ntransfer-encoding: chunked\r\n\r\n14\r\nHello from config.ru\r\n0\r\n\r\n", resp
  ensure
    machine.close(sock) rescue nil
    if pid
      Process.kill('SIGTERM', pid)
      Process.wait(pid)
    end
  end

  def test_cli_serve_roda1
    port = random_port

    pid = fork_server(
      File.join(__dir__, 'apps/roda1.ru'),
      bind: "127.0.0.1:#{port}"
    )

    resp = make_request(
      '127.0.0.1', port,
      "GET /foo HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 404\r\ncontent-type: text/html\r\ncontent-length: 0\r\n\r\n", resp

    resp = make_request(
      '127.0.0.1', port,
      "GET / HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 302\r\nlocation: /hello\r\ncontent-type: text/html\r\ncontent-length: 0\r\n\r\n", resp

    resp = make_request(
      '127.0.0.1', port,
      "GET /hello HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 200\r\ncontent-type: text/html\r\ncontent-length: 6\r\n\r\nHello!", resp

    resp = make_request(
      '127.0.0.1', port,
      "GET /hello/world HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 200\r\ncontent-type: text/html\r\ncontent-length: 12\r\n\r\nHello world!", resp

    resp = make_request(
      '127.0.0.1', port,
      "POST /hello HTTP/1.1\r\n\r\n"
    )
    assert_equal "HTTP/1.1 302\r\nlocation: /hello\r\ncontent-type: text/html\r\ncontent-length: 0\r\n\r\n", resp
  ensure
    machine.close(sock) rescue nil
    if pid
      Process.kill('SIGTERM', pid)
      Process.wait(pid)
    end
  end
end
