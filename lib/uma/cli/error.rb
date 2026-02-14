
# frozen_string_literal: true

module Uma
  module CLI
    module Error
      class Base < StandardError; end

      class NoCommand < Base; end
    end
  end
end
