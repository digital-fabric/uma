# frozen_string_literal: true

require 'uma/cli/error'
require 'uma/version'

module Uma
  module CLI
    def self.run(argv, env)
      cmd = argv[0]
      argv = argv[1..-1]

      case cmd
      when 'help'
        Help.new(argv, env).run
      when '', nil
        raise Error::NoCommand
      else
        raise Error::InvalidCommand, "unrecognized command '#{cmd}'"
      end
    rescue => e
      if env[:error_handler]
        env[:error_handler].(e)
      else
        ErrorResponse.new(e, argv, env).run
      end
    end

    class Base
      attr_reader :argv, :env

      def initialize(argv, env)
        @argv = argv
        @env = env
      end      
    end

    HELP = <<~EOF
           ●
        ●╭───╮●
         │UMA│   A modern web server for Ruby
        ●╰───╯●  https://uma.noteflakes.com/
           ●
      
      Uma version #{Uma::VERSION}

      Usage: uma <COMMAND>

      Commands:
        serve          Run a Rack application
        help           Print this message or the help of the given subcommand(s)
    EOF

    class Help < Base
      def run        
        env[:io_out] << HELP
      end
    end
  end
end
