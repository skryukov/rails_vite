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
      stub_build(->(*) { built = true }) do
        middleware = RailsVite::AutoBuild.new(@app, @config)
        middleware.call({})
      end

      assert built
    end
  end

  def test_skips_build_when_manifest_is_newer_than_sources
    write_manifest(mtime: Time.now)
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now - 10)

    with_root do
      built = false
      stub_build(->(*) { built = true }) do
        middleware = RailsVite::AutoBuild.new(@app, @config)
        middleware.call({})
      end

      refute built
    end
  end

  def test_builds_when_sources_newer_than_manifest
    write_manifest(mtime: Time.now - 10)
    FileUtils.touch(File.join(@source_dir, "app.js"), mtime: Time.now)

    with_root do
      built = false
      stub_build(->(*) { built = true }) do
        middleware = RailsVite::AutoBuild.new(@app, @config)
        middleware.call({})
      end

      assert built
    end
  end

  def test_skips_build_across_middleware_instances_when_inputs_unchanged
    with_root do
      first_build = false
      stub_build(->(*) {
        first_build = true
        write_manifest
      }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      second_build = false
      stub_build(->(*) { second_build = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert first_build
      refute second_build
    end
  end

  def test_builds_when_sources_change_after_cached_build
    with_root do
      stub_build(->(*) { write_manifest }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      File.write(File.join(@source_dir, "app.js"), "console.log('changed')")

      built = false
      stub_build(->(*) { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_builds_when_source_digest_changes_with_old_mtime
    with_root do
      stub_build(->(*) { write_manifest }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      source_file = File.join(@source_dir, "app.js")
      File.write(source_file, "console.log('changed')")
      FileUtils.touch(source_file, mtime: File.mtime(@manifest_path) - 10)

      built = false
      stub_build(->(*) { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_builds_when_config_changes_after_cached_build
    with_root do
      stub_build(->(*) { write_manifest }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      File.write(File.join(@dir, "vite.config.ts"), "export default {}")

      built = false
      stub_build(->(*) { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_builds_when_build_input_changes_after_cached_build
    build_input = File.join(@dir, "frontend/custom.js")
    FileUtils.mkdir_p(File.dirname(build_input))
    File.write(build_input, "console.log('custom')")
    write_build_meta(build_inputs: ["frontend/custom.js"])

    with_root do
      stub_build(->(*) { write_manifest }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      File.write(build_input, "console.log('custom changed')")

      built = false
      stub_build(->(*) { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_skips_build_when_source_dir_missing_but_build_inputs_are_fresh
    build_input = File.join(@dir, "frontend/custom.js")
    FileUtils.mkdir_p(File.dirname(build_input))
    File.write(build_input, "console.log('custom')")
    FileUtils.rm_rf(@source_dir)
    write_build_meta(build_inputs: ["frontend/custom.js"])

    with_root do
      stub_build(->(*) { write_manifest }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      built = false
      stub_build(->(*) { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      refute built
    end
  end

  def test_builds_when_configured_build_input_is_missing
    write_manifest
    write_build_meta(build_inputs: ["frontend/missing.js"])

    with_root do
      built = false
      stub_build(->(*) { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_does_not_cache_failed_build
    with_root do
      stub_build(->(*) { false }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      refute File.exist?(@config.auto_build_cache_path)

      built = false
      stub_build(->(*) {
        built = true
        write_manifest
      }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      assert built
    end
  end

  def test_does_not_cache_successful_build_without_manifest
    with_root do
      stub_build(->(*) { true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end

      refute File.exist?(@config.auto_build_cache_path)
    end
  end

  def test_builds_when_source_dir_missing
    FileUtils.rm_rf(@source_dir)
    File.write(@manifest_path, "{}")

    with_root do
      built = false
      stub_build(->(*) { built = true }) do
        middleware = RailsVite::AutoBuild.new(@app, @config)
        middleware.call({})
      end

      assert built
    end
  end

  def test_passes_request_through_to_app
    write_manifest(mtime: Time.now)

    with_root do
      middleware = RailsVite::AutoBuild.new(@app, @config)

      status, = middleware.call({})
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

  def write_build_meta(build_inputs: [])
    File.write(
      @manifest_path.dirname.join("rails-vite.json"),
      JSON.generate({buildInputs: build_inputs})
    )
  end

  def stub_build(callback)
    RailsVite::Tasks.stub(:build_command, "true") do
      RailsVite::AutoBuild.define_method(:system) do |*args|
        result = callback.call(*args)
        result != false
      end
      yield
    ensure
      RailsVite::AutoBuild.remove_method(:system)
    end
  end
end
