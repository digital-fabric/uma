
# frozen_string_literal: true

require_relative 'helper'
require 'uma/cli'

class CLITest < Minitest::Test
  def setup
    @env = {
      io_out: StringIO.new,
      io_err: StringIO.new,
      error_handler: ->(e) { raise e }
    }
  end

  CLI = Uma::CLI
  E = CLI::Error

  def test_cli_missing_command
    assert_raises(E::NoCommand) { CLI.run([], @env) }
  end
end
