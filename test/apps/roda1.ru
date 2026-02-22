# frozen_string_literal: true

require "roda"
require "irb"

# Demo app copied from Roda website:
# https://roda.jeremyevans.net/
class App < Roda
  route do |r|
    # GET / request
    r.root do
      r.redirect "/hello"
    end

    # /hello branch
    r.on "hello" do
      # Set variable for all routes in /hello branch
      @greeting = 'Hello'

      # GET /hello/world request
      r.get "world" do
        "#{@greeting} world!"
      end

      # /hello request
      r.is do
        # GET /hello request
        r.get do
          "#{@greeting}!"
        end

        # POST /hello request
        r.post do
          r.redirect
        end
      end
    end
  end
end

run App.freeze.app
