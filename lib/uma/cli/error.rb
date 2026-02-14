
# frozen_string_literal: true

module Uma
  module CLI
    module Error
      class Base < StandardError; end

      class NoCommand < Base; end
      class InvalidCommand < Base; end
    end
  end
end
