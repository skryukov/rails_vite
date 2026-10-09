require "test_helper"

class ConfigTest < Minitest::Test
  def setup
    @config = RailsVite::Config.new
  end

  def test_default_dev_meta_path
    assert_equal Rails.root.join("tmp/rails-vite.json"), @config.dev_meta_path
  end

  def test_default_manifest_path
    assert_equal Rails.root.join("public/vite/manifest.json"), @config.manifest_path
  end

  def test_default_asset_prefix
    assert_equal "/vite", @config.asset_prefix
  end

  def test_default_build_mode_is_nil_outside_test
    refute Rails.env.test?
    assert_nil @config.build_mode
  end

  def test_default_build_mode_is_test_in_test
    with_env("test") do
      assert_equal "test", @config.build_mode
      assert_equal "vite-test", @config.build_dir
    end
  end

  def test_custom_build_mode
    @config.build_mode = "e2e"
    assert_equal "e2e", @config.build_mode
  end

  def test_build_mode_nil_or_false_means_no_mode
    with_env("test") do
      @config.build_mode = nil
      assert_nil @config.build_mode

      @config.build_mode = false
      assert_nil @config.build_mode
    end
  end

  def test_build_dir_and_manifest_path_do_not_depend_on_build_mode
    with_env("test") do
      @config.build_mode = nil
      assert_equal "vite-test", @config.build_dir
      assert_equal Rails.root.join("public/vite-test/manifest.json"), @config.manifest_path
      assert_equal "/vite-test", @config.asset_prefix
    end
  end

  def test_default_vite_executable
    assert_equal "vite", @config.vite_executable
  end

  def test_custom_vite_executable
    @config.vite_executable = "vp"
    assert_equal "vp", @config.vite_executable
  end

  def test_custom_dev_meta_path
    @config.dev_meta_path = Rails.root.join("tmp/custom-vite.json")
    assert_equal Rails.root.join("tmp/custom-vite.json"), @config.dev_meta_path
  end

  def test_custom_manifest_path
    @config.manifest_path = Rails.root.join("public/custom/.vite/manifest.json")
    assert_equal Rails.root.join("public/custom/.vite/manifest.json"), @config.manifest_path
  end

  def test_custom_asset_prefix
    @config.asset_prefix = "/custom"
    assert_equal "/custom", @config.asset_prefix
  end

  def test_default_auto_build_paths
    assert_includes @config.auto_build_paths, "vite.config.*"
    assert_includes @config.auto_build_paths, "package.json"
    assert_includes @config.auto_build_paths, "pnpm-lock.yaml"
  end

  def test_custom_auto_build_paths
    @config.auto_build_paths = ["app/views"]
    assert_equal ["app/views"], @config.auto_build_paths
  end

  def test_dev_server_not_running_without_dev_meta
    refute @config.dev_server_running?
  end

  def test_dev_server_running_with_dev_meta
    Dir.mktmpdir do |dir|
      meta = File.join(dir, "rails-vite.json")
      File.write(meta, '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')
      @config.dev_meta_path = Pathname.new(meta)

      assert @config.dev_server_running?
      assert_equal "http://localhost:5173", @config.dev_server_url
    end
  end

  def test_dev_server_running_with_live_pid
    with_dev_meta(pid: Process.pid) do
      assert @config.dev_server_running?
      assert_equal "http://localhost:5173", @config.dev_server_url
    end
  end

  def test_dev_server_not_running_with_dead_pid
    with_dev_meta(pid: dead_pid, hostname: Socket.gethostname) do
      refute @config.dev_server_running?
      assert_nil @config.dev_server_url
    end
  end

  def test_dev_server_running_with_dead_pid_from_another_host
    with_dev_meta(pid: dead_pid, hostname: "#{Socket.gethostname}-other") do
      assert @config.dev_server_running?
    end
  end

  def test_dev_server_running_with_dead_pid_without_hostname
    with_dev_meta(pid: dead_pid) do
      assert @config.dev_server_running?
    end
  end

  def test_dead_pid_falls_back_to_build_meta
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "rails-vite.json"), '{"sourceDir":"app/frontend"}')
      @config.manifest_path = Pathname.new(File.join(dir, "manifest.json"))

      with_dev_meta(pid: dead_pid, hostname: Socket.gethostname) do
        assert_equal "app/frontend", @config.source_dir
      end
    end
  end

  def test_dev_server_running_with_non_integer_pid
    with_dev_meta(pid: "123") do
      assert @config.dev_server_running?
    end
  end

  def test_dev_server_url_nil_when_not_running
    assert_nil @config.dev_server_url
  end

  def test_default_source_dir
    assert_equal "app/javascript", @config.source_dir
  end

  def test_source_dir_from_dev_meta
    Dir.mktmpdir do |dir|
      meta = File.join(dir, "rails-vite.json")
      File.write(meta, '{"url":"http://localhost:5173","sourceDir":"app/frontend"}')
      @config.dev_meta_path = Pathname.new(meta)

      assert_equal "app/frontend", @config.source_dir
    end
  end

  def test_source_dir_from_build_meta
    Dir.mktmpdir do |dir|
      vite_dir = File.join(dir, ".vite")
      FileUtils.mkdir_p(vite_dir)
      File.write(File.join(vite_dir, "manifest.json"), "{}")
      File.write(File.join(vite_dir, "rails-vite.json"), '{"sourceDir":"app/frontend"}')

      @config.manifest_path = Pathname.new(File.join(vite_dir, "manifest.json"))

      assert_equal "app/frontend", @config.source_dir
    end
  end

  def test_auto_build_true_in_local_env
    assert Rails.env.local?
    assert @config.auto_build?
  end

  def test_auto_build_respects_explicit_false
    @config.auto_build = false
    refute @config.auto_build?
  end

  def test_react_refresh_false_by_default
    refute @config.react_refresh?
  end

  def test_react_refresh_from_dev_meta
    Dir.mktmpdir do |dir|
      meta = File.join(dir, "rails-vite.json")
      File.write(meta, '{"url":"http://localhost:5173","sourceDir":"app/javascript","reactRefresh":true}')
      @config.dev_meta_path = Pathname.new(meta)

      assert @config.react_refresh?
    end
  end

  def test_react_refresh_false_without_flag
    Dir.mktmpdir do |dir|
      meta = File.join(dir, "rails-vite.json")
      File.write(meta, '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')
      @config.dev_meta_path = Pathname.new(meta)

      refute @config.react_refresh?
    end
  end

  def test_ssr_output_dir_nil_by_default
    assert_nil @config.ssr_output_dir
  end

  def test_ssr_output_dir_from_dev_meta
    Dir.mktmpdir do |dir|
      meta = File.join(dir, "rails-vite.json")
      File.write(meta, '{"url":"http://localhost:5173","sourceDir":"app/javascript","ssrOutputDir":"ssr"}')
      @config.dev_meta_path = Pathname.new(meta)

      assert_equal "ssr", @config.ssr_output_dir
    end
  end

  def test_ssr_output_dir_from_build_meta
    Dir.mktmpdir do |dir|
      vite_dir = File.join(dir, ".vite")
      FileUtils.mkdir_p(vite_dir)
      File.write(File.join(vite_dir, "manifest.json"), "{}")
      File.write(File.join(vite_dir, "rails-vite.json"), '{"sourceDir":"app/javascript","ssrOutputDir":"ssr"}')

      @config.manifest_path = Pathname.new(File.join(vite_dir, "manifest.json"))

      assert_equal "ssr", @config.ssr_output_dir
    end
  end

  private

  def with_env(env, &block)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new(env), &block)
  end

  def with_dev_meta(**extra)
    Dir.mktmpdir do |dir|
      meta = File.join(dir, "rails-vite.json")
      File.write(meta, JSON.generate({url: "http://localhost:5173", sourceDir: "app/javascript", **extra}))
      @config.dev_meta_path = Pathname.new(meta)
      yield
    end
  end

  def dead_pid
    pid = Process.spawn("true")
    Process.wait(pid)
    pid
  end
end
