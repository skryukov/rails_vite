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
    with_root do
      built = false
      stub_build(-> { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_runs_the_build_quietly
    captured = nil
    with_root do
      RailsVite::Tasks.stub(:build_command, "vite build") do
        RailsVite::AutoBuild.define_method(:system) do |cmd|
          captured = cmd
          true
        end
        RailsVite::AutoBuild.new(@app, @config).call({})
      ensure
        RailsVite::AutoBuild.remove_method(:system)
      end
    end

    assert_includes captured, "--logLevel warn"
  end

  def test_builds_when_sources_are_newer_than_manifest
    write_manifest(mtime: Time.now - 10)
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now)

    with_root do
      built = false
      stub_build(-> { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_skips_build_when_manifest_is_newer_than_sources
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now - 10)
    write_manifest(mtime: Time.now)

    with_root do
      built = false
      stub_build(-> { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      refute built
    end
  end

  def test_skips_build_across_instances_when_nothing_changed
    # Issue #21: a fresh middleware instance (a new Rails process, e.g. each
    # local system-test run) must not rebuild when assets are unchanged. The
    # freshness signal is the manifest's on-disk mtime, so it persists.
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now - 10)

    with_root do
      first_build = false
      stub_build(-> {
        first_build = true
        write_manifest
      }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      second_build = false
      stub_build(-> { second_build = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert first_build
      refute second_build
    end
  end

  def test_missing_source_dir_triggers_build
    FileUtils.rm_rf(@source_dir)
    write_manifest(mtime: Time.now)

    with_root do
      built = false
      stub_build(-> { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_passes_request_through_to_app
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now - 10)
    write_manifest(mtime: Time.now)

    with_root do
      status, = RailsVite::AutoBuild.new(@app, @config).call({})
      assert_equal 200, status
    end
  end

  private

  def with_root(&block)
    Rails.stub(:root, Pathname.new(@dir), &block)
  end

  def write_manifest(mtime: Time.now)
    File.write(@manifest_path, "{}")
    FileUtils.touch(@manifest_path, mtime: mtime)
  end

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
