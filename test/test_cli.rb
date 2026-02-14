
# frozen_string_literal: true

require_relative 'helper'
require 'uma/cli'
require 'uma/version'

class CLITest < Minitest::Test
  def setup
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

  class MockSupervisor
    def initialize(env)
      @env = env
    end

    def start
      @env[:h][:env] = @env
    end
  end

  def test_cli_version
    cli_cmd_raise('version')
    assert_equal "Uma version #{Uma::VERSION}\n", read_io(@io_out)
  end

  def test_cli_serve
    @env[:h] = {}
    @env[:supervisor_class] = MockSupervisor
    
    cli_cmd_raise('serve')
    assert_kind_of Hash, @env[:h][:env]
  end

  def test_cli_serve_controller
    @env[:h] = {}
    @env[:norun] = true
    
    controller = cli_cmd_raise('serve')
    assert_kind_of Uma::CLI::Serve, controller

    supervisor = controller.supervisor
    assert_kind_of Uma::Supervisor, supervisor
  end
end
