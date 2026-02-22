# frozen_string_literal: true

require_relative 'helper'
require 'uma/app'

class AppTest < UMBaseTest
  App = Uma::App

  def test_app
    fn = File.join(__dir__, 'simple.ru')
    app = App.new(fn)

    assert_kind_of App, app
    assert_equal [200, {}, 'simple'], app.to_proc.({})
  end

  def test_app_bad_filename
    fn = File.join(__dir__, 'simple2.ru')
    assert_raises(Uma::Error) { App.new(fn) }
  end

  def test_app_invalid_syntax
    fn = File.join(__dir__, 'bad_syntax.ru')
    assert_raises(Uma::Error) { App.new(fn) }
  end
end
