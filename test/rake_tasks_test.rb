require "test_helper"
require "rake"

class RakeTasksTest < Minitest::Test
  BUILD_RAKE = File.expand_path("../lib/tasks/rails_vite/build.rake", __dir__)

  def setup
    @original_rake = Rake.application
    Rake.application = Rake::Application.new
    @config = RailsVite::Config.new
    config = @config
    Rake::Task.define_task(:environment) do
      config.vite_executable = "vp"
    end
    load BUILD_RAKE
  end

  def teardown
    Rake.application = @original_rake
  end

  def test_build_uses_config_from_the_app
    calls = []
    main = TOPLEVEL_BINDING.receiver
    main.define_singleton_method(:system) do |*args, **|
      calls << args
      true
    end

    RailsVite.stub(:config, @config) do
      RailsVite::Tasks.stub(:tool, :npm) do
        Rake::Task["vite:build"].invoke
      end
    end

    assert_equal ["npx vp build"], calls.last
  ensure
    main.singleton_class.remove_method(:system)
  end
end
