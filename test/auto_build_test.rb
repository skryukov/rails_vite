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
    @base_time = Time.now - 100
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
        RailsVite::AutoBuild.define_method(:system) do |*args, **|
          captured = args
          true
        end
        RailsVite::AutoBuild.new(@app, @config).call({})
      ensure
        RailsVite::AutoBuild.remove_method(:system)
      end
    end

    assert_includes captured.last, "--logLevel warn"
  end

  def test_passes_the_build_dir_to_the_build
    captured = nil
    with_root do
      RailsVite::Tasks.stub(:build_command, "vite build") do
        RailsVite::AutoBuild.define_method(:system) do |*args, **|
          captured = args
          true
        end
        RailsVite::AutoBuild.new(@app, @config).call({})
      ensure
        RailsVite::AutoBuild.remove_method(:system)
      end
    end

    assert_equal({"RAILS_VITE_BUILD_DIR" => RailsVite.config.build_dir}, captured.first)
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

  def test_default_paths_include_root_build_config
    assert built_after_changing("vite.config.ts")
    assert built_after_changing("pnpm-lock.yaml")
  end

  def test_default_paths_exclude_app_directories
    refute built_after_changing("app/views/home/index.html.erb")
  end

  def test_builds_when_a_file_in_an_extra_directory_is_newer
    @config.auto_build_paths += ["app/views"]

    assert built_after_changing("app/views/home/index.html.erb")
  end

  def test_builds_when_a_glob_match_is_newer
    @config.auto_build_paths += ["config/vite_*.mts"]

    assert built_after_changing("config/vite_plugins.mts")
  end

  def test_ignores_missing_extra_paths
    @config.auto_build_paths += ["app/components", "config/missing_*.js"]
    File.utime(@base_time, @base_time, File.join(@source_dir, "app.js"))
    write_manifest(mtime: @base_time + 10)

    refute built?
  end

  def test_ignores_broken_symlinks_in_extra_paths
    File.symlink(File.join(@dir, "missing.js"), File.join(@dir, "vite.config.js"))
    File.utime(@base_time, @base_time, File.join(@source_dir, "app.js"))
    write_manifest(mtime: @base_time + 10)

    refute built?
  end

  def test_builds_when_a_file_in_a_symlinked_extra_directory_is_newer
    @config.auto_build_paths += ["app/views"]
    write_input("shared/views/home/index.html.erb", mtime: @base_time)
    File.symlink(File.join(@dir, "shared/views"), File.join(@dir, "app/views"))

    assert built_after_changing("shared/views/home/index.html.erb")
  end

  def test_skips_build_when_extra_paths_are_older_than_manifest
    @config.auto_build_paths += ["app/views"]
    write_input("app/views/home/index.html.erb", mtime: @base_time)
    File.utime(@base_time, @base_time, File.join(@source_dir, "app.js"))
    write_manifest(mtime: @base_time + 10)

    refute built?
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

  # Source and manifest at the base time, the given input 10 seconds newer.
  def built_after_changing(relative_path)
    File.utime(@base_time, @base_time, File.join(@source_dir, "app.js"))
    write_manifest(mtime: @base_time)
    write_input(relative_path, mtime: @base_time + 10)
    built?
  end

  def write_input(relative_path, mtime:)
    path = File.join(@dir, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "")
    File.utime(mtime, mtime, path)
  end

  def built?
    built = false
    with_root do
      stub_build(-> { built = true }) do
        RailsVite::AutoBuild.new(@app, @config).call({})
      end
    end
    built
  end

  def write_manifest(mtime: Time.now)
    File.write(@manifest_path, "{}")
    FileUtils.touch(@manifest_path, mtime: mtime)
  end

  def stub_build(callback)
    RailsVite::Tasks.stub(:build_command, "true") do
      RailsVite::AutoBuild.define_method(:system) do |*, **|
        callback.call
        true
      end
      yield
    ensure
      RailsVite::AutoBuild.remove_method(:system)
    end
  end
end
