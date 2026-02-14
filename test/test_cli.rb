
# frozen_string_literal: true

require_relative 'helper'
require 'uma/cli'

class CLITest < Minitest::Test
  def setup
    @io_out = StringIO.new
    @io_err = StringIO.new
    @env = {
      io_out: @io_out,
      io_err: @io_err
    }
    @env_raise = @env.merge(
      error_handler: ->(e) { raise e }
    )
  end

  def read_io(io)
    io.rewind
    io.read
  end

  def cli_run(argv)
    CLI.run(argv, @env)
  end

  def cli_run_raise(argv)
    CLI.run(argv, @env_raise)
  end

  CLI = Uma::CLI
  E = CLI::Error

  def test_cli_no_command
    assert_raises(E::NoCommand) { cli_run_raise([]) }

    cli_run([])
    assert_match(/│UMA│/, read_io(@io_err))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_err))
  end

  def test_cli_invalid_command
    assert_raises(E::InvalidCommand) { cli_run_raise(['foo']) }

    cli_run(['foo'])
    assert_match(/Error\: unrecognized command/, read_io(@io_err))
    assert_match(/Usage: uma \<COMMAND\>/, read_io(@io_err))
  end
end
