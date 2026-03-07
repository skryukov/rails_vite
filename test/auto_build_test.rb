require "test_helper"
require "rails_vite/auto_build"

class AutoBuildTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    @source_dir = File.join(@dir, "app/javascript")
    FileUtils.mkdir_p(@source_dir)
    File.write(File.join(@source_dir, "app.js"), "console.log('hi')")

    @manifest_path = Pathname.new(File.join(@dir, "public/vite/manifest.json"))
    FileUtils.mkdir_p(@manifest_path.dirname)

    @config = RailsVite::Config.new
    @config.manifest_path = @manifest_path

    @app = ->(env) { [200, {}, ["OK"]] }
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_builds_when_manifest_missing
    built = false
    stub_build(-> { built = true }) do
      middleware = RailsVite::AutoBuild.new(@app, @config)
      middleware.call({})
    end

    assert built
  end

  def test_builds_when_sources_newer_than_last_build
    File.write(@manifest_path, "{}")

    middleware = RailsVite::AutoBuild.new(@app, @config)

    # Simulate a previous build
    middleware.instance_variable_set(:@last_build_at, Time.now - 10)
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now)

    built = false
    stub_build(-> { built = true }) do
      middleware.call({})
    end

    assert built
  end

  def test_skips_build_when_manifest_fresh
    File.write(@manifest_path, "{}")

    middleware = RailsVite::AutoBuild.new(@app, @config)
    middleware.instance_variable_set(:@last_build_at, Time.now + 10)

    built = false
    stub_build(-> { built = true }) do
      middleware.call({})
    end

    refute built
  end

  def test_missing_source_dir_triggers_build
    FileUtils.rm_rf(@source_dir)
    File.write(@manifest_path, "{}")

    middleware = RailsVite::AutoBuild.new(@app, @config)
    middleware.instance_variable_set(:@last_build_at, Time.at(0))

    built = false
    stub_build(-> { built = true }) do
      middleware.call({})
    end

    assert built
  end

  def test_passes_request_through_to_app
    File.write(@manifest_path, "{}")

    middleware = RailsVite::AutoBuild.new(@app, @config)
    middleware.instance_variable_set(:@last_build_at, Time.now + 10)

    status, = middleware.call({})
    assert_equal 200, status
  end

  private

  def stub_build(callback)
    RailsVite::Tasks.stub(:build_command, "true") do
      RailsVite::AutoBuild.define_method(:system) do |cmd|
        callback.call
        true
      end
      yield
    ensure
      RailsVite::AutoBuild.remove_method(:system)
    end
  end
end
