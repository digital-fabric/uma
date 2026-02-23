# frozen_string_literal: true

require 'uma/http'
require 'uma/error'

module Uma
  class App
    def initialize(fn)
      @fn = fn
      eval_app_code
    end

    def run(proc)
      @proc = proc
    end

    def connection_proc
      ->(machine, fd) {
        HTTP.http_connection(machine, { app: @proc }, fd)
      }
    end

    def to_proc = @proc

    private

    def get_code
      IO.read(@fn)
    rescue SystemCallError
      raise Uma::Error, "Could not load Rackup file"
    end

    def eval_app_code
      eval(get_code, binding, @fn)
    rescue SyntaxError, NameError => e
      raise Uma::Error, e.message
    end
  end
end
