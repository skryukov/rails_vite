# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"

# require "tmpdir"
# require "json"
# require "fileutils"

require "rails"
require "action_controller/railtie"
require "action_view"

# Minimal Rails app for testing
class TestApp < Rails::Application
  config.eager_load = false
  config.active_support.deprecation = :stderr
end

TestApp.initialize!

require "rails_vite"
