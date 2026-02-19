
# frozen_string_literal: true

require_relative 'helper'
require 'uma/cli'
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

  def test_cli_serve_running
    port = random_port
    
    @env.merge!(
      bind: "127.0.0.1:#{port}",
      connection_proc: ->(machine, fd) {
        machine.write(fd, "foo")
      }
    )
    
    pid = fork {
      cli_cmd_raise('serve')
    }

    machine.sleep(0.08)

    sock1 = machine.socket(UM::AF_INET, UM::SOCK_STREAM, 0, 0)
    res = machine.connect(sock1, '127.0.0.1', port)
    assert_equal 0, res
    buf = +''
    machine.recv(sock1, buf, 128, 0)
    assert_equal 'foo', buf
  ensure
    machine.close(sock1) rescue nil
    if pid
      Process.kill('SIGTERM', pid)
      Process.wait(pid)
    end
  end
end
