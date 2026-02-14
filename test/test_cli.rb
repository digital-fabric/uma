
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

  def cli_run(*argv)
    env = @env.merge(
      io_out: (@io_out = StringIO.new),
      io_err: (@io_err = StringIO.new)
    )

    argv = argv.first if argv.size == 1 && argv.first.is_a?(Array)
    CLI.run(argv, env)
  end

  def cli_run_raise(*argv)
    env = @env.merge(
      io_out: (@io_out = StringIO.new),
      io_err: (@io_err = StringIO.new),
      error_handler: ->(e) { raise e }
    )

    argv = argv.first if argv.size == 1 && argv.first.is_a?(Array)
    CLI.run(argv, env)
  end

  CLI = Uma::CLI
  E = CLI::Error

  def test_cli_no_command
    assert_raises(E::NoCommand) { cli_run_raise() }

    cli_run()
    assert_match(/│UMA│/, read_io(@io_err))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_err))
  end

  def test_cli_invalid_command
    assert_raises(E::InvalidCommand) { cli_run_raise('foo') }

    cli_run('foo')
    assert_match(/Error\: unrecognized command/, read_io(@io_err))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_err))
  end

  def test_cli_help
    cli_run_raise('help')
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

  def test_cli_serve
    # we only check that the commands starts a supervisor

    @env[:h] = {}
    @env[:supervisor_class] = MockSupervisor
    
    cli_run_raise('serve')
    assert_kind_of Hash, @env[:h][:env]
  end

  def test_cli_version
    cli_run_raise('version')
    assert_equal "Uma version #{Uma::VERSION}\n", read_io(@io_out)
  end
end
