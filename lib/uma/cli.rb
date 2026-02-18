# frozen_string_literal: true

require 'uma/cli/error'
require 'uma/version'
require 'uma/server'
require 'optparse'

module Uma
  module CLI
    def self.call(argv, env)
      setup_controller(argv, env).tap {
        it.run if !env[:norun]
      }
    end

    def self.setup_controller(argv, env)
      cmd = argv[0]
      argv = argv[1..-1]

      case cmd
      when 'help'
        Help.new(argv, env)
      when 'serve'
        Serve.new(argv, env)
      when 'version'
        Version.new(argv, env)
      when '', nil
        raise Error::NoCommand, ''
      else
        raise Error::InvalidCommand, "unrecognized command '#{cmd}'"
      end
    rescue => e
      if env[:error_handler]
        env[:error_handler].(e)
      else
        ErrorResponse.new(e, argv, env)
      end
    end

    class Base
      attr_reader :argv, :env

      def initialize(argv, env)
        @argv = argv
        @env = env
      end

      def print_message(io, template, **)
        io << "#{format(template, **)}\n"
      end
    end

    CLI_HELP = <<~EOF

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
        print_message(env[:io_out], CLI_HELP)
      end
    end

    ERROR_RESPONSE_TEMPLATE = <<~EOF
      Error: %<error_msg>s

      Usage: uma <COMMAND>

      Commands:
        serve          Run a Rack application
        help           Print this message or the help of the given subcommand(s)
    EOF

    class ErrorResponse < Base
      def initialize(error, argv, env)
        @error = error
        @argv = argv
        @env = env
      end

      def run
        error_msg = @error.message
        if error_msg.empty?
          print_message(env[:io_err], CLI_HELP)
        else
          print_message(
            env[:io_err], ERROR_RESPONSE_TEMPLATE,
            error_msg:
          )
        end
      end
    end

    class Version < Base
      def run
        print_message(env[:io_out], "Uma version #{Uma::VERSION}")
      end
    end

    SERVE_BANNER = <<~EOF

           ●
        ●╭───╮●
         │UMA│   A modern web server for Ruby
        ●╰───╯●  https://uma.noteflakes.com/
           ●

      Uma version #{Uma::VERSION}
    EOF

    class Serve < Base
      attr_reader :server

      def initialize(argv, env)
        super
        server_class = env[:server_class] || Uma::Server
        @server = server_class.new(@env)
      end

      def run
        parse_argv

        print_message(@env[:io_err], SERVE_BANNER)
        @server.start
      rescue => e
        if env[:error_handler]
          env[:error_handler].(e)
        else
          ErrorResponse.new(e, @argv, @env).run
        end
      end

      private

      HELP_BANNER = <<~EOF

             ●
          ●╭───╮●
           │UMA│   A modern web server for Ruby
          ●╰───╯●  https://uma.noteflakes.com/
             ●

        Usage: uma serve [OPTIONS] app.ru

      EOF

      def parse_argv
        parser = OptionParser.new() do |o|
          o.banner = HELP_BANNER

          o.on('-b', '--bind BIND', String,
            'Bind address (default: http://0.0.0.0:1234). You can specify this flag multiple times to bind to multiple addresses.') do
            @env[:bind] ||= []
            @env[:bind] << it
          end

          o.on('-s', '--silent', 'Silent mode') do
            @env[:silent] = true
          end

          o.on('-h', '--help', 'Show this help message') do
            puts o
            exit
          end

          o.on('--no-server-headers', 'Don\'t include Server and Date headers') do
            @env[:server_extensions] = false
          end
        end

        parser.parse!(argv)
      end
    end
  end
end
