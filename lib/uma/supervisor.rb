# frozen_string_literal: true

module Uma
  class Supervisor
    def initialize(env)
      @env = env
    end

    def start
      sleep(1)
      puts "Done..."
    end
  end
end
