require "test_helper"

class TasksTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @dir = Dir.mktmpdir
    Dir.chdir(@dir)
    @original_root = Rails.application.config.root
    Rails.application.config.root = @dir
  end

  def teardown
    Rails.application.config.root = @original_root
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@dir)
  end

  def test_detects_bun_from_bun_lockb
    FileUtils.touch("bun.lockb")
    assert_equal :bun, RailsVite::Tasks.tool
  end

  def test_detects_bun_from_bun_lock
    FileUtils.touch("bun.lock")
    assert_equal :bun, RailsVite::Tasks.tool
  end

  def test_detects_yarn_from_yarn_lock
    FileUtils.touch("yarn.lock")
    assert_equal :yarn, RailsVite::Tasks.tool
  end

  def test_detects_pnpm_from_pnpm_lock
    FileUtils.touch("pnpm-lock.yaml")
    assert_equal :pnpm, RailsVite::Tasks.tool
  end

  def test_detects_npm_from_package_lock
    FileUtils.touch("package-lock.json")
    assert_equal :npm, RailsVite::Tasks.tool
  end

  def test_detects_aube_from_aube_lock
    FileUtils.touch("aube-lock.yaml")
    assert_equal :aube, RailsVite::Tasks.tool
  end

  def test_bun_lockfile_takes_priority
    FileUtils.touch("bun.lockb")
    FileUtils.touch("yarn.lock")
    assert_equal :bun, RailsVite::Tasks.tool
  end

  def test_aube_lockfile_takes_priority
    FileUtils.touch("aube-lock.yaml")
    FileUtils.touch("bun.lock")
    FileUtils.touch("pnpm-lock.yaml")
    assert_equal :aube, RailsVite::Tasks.tool
  end

  def test_install_command
    FileUtils.touch("yarn.lock")
    assert_equal "yarn install", RailsVite::Tasks.install_command
  end

  def test_dev_command
    FileUtils.touch("yarn.lock")
    assert_equal "yarn vite dev", RailsVite::Tasks.dev_command
  end

  def test_build_command
    FileUtils.touch("yarn.lock")
    assert_equal "yarn vite build", RailsVite::Tasks.build_command
  end

  def test_add_command_appends_packages
    FileUtils.touch("yarn.lock")
    assert_equal "yarn add -D vite @vitejs/plugin-react", RailsVite::Tasks.add_command("vite", "@vitejs/plugin-react")
  end

  def test_npm_commands
    FileUtils.touch("package-lock.json")
    assert_equal "npm install", RailsVite::Tasks.install_command
    assert_equal "npm install -D vite", RailsVite::Tasks.add_command("vite")
    assert_equal "npx vite dev", RailsVite::Tasks.dev_command
    assert_equal "npx vite build", RailsVite::Tasks.build_command
  end

  def test_pnpm_commands
    FileUtils.touch("pnpm-lock.yaml")
    assert_equal "pnpm install", RailsVite::Tasks.install_command
    assert_equal "pnpm add -D vite", RailsVite::Tasks.add_command("vite")
    assert_equal "pnpm vite dev", RailsVite::Tasks.dev_command
    assert_equal "pnpm vite build", RailsVite::Tasks.build_command
  end

  def test_precompile_command_prefers_package_json_build_script
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: "vite build && vite build --ssr"})
    assert_equal "npm run build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_run_forms_per_package_manager
    write_package_json(scripts: {build: "vite build"})

    {"yarn.lock" => "yarn run build",
     "pnpm-lock.yaml" => "pnpm run build",
     "bun.lock" => "bun run build",
     "aube-lock.yaml" => "aube run build"}.each do |lockfile, expected|
      FileUtils.touch(lockfile)
      assert_equal expected, RailsVite::Tasks.precompile_command
      FileUtils.rm(lockfile)
    end
  end

  def test_precompile_command_reads_package_json_from_rails_root
    write_package_json(scripts: {build: "vite build"})
    Dir.mktmpdir do |cwd|
      Dir.chdir(cwd) do
        FileUtils.touch("package-lock.json")
        assert_equal "npm run build", RailsVite::Tasks.precompile_command
      end
    end
  end

  def test_precompile_command_falls_back_without_build_script
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {dev: "vite"})
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_without_package_json
    FileUtils.touch("package-lock.json")
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_on_empty_build_script
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: ""})
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_on_blank_build_script
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: "   "})
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_when_scripts_is_not_an_object
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: "vite build")
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_on_non_string_build_script
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: 5})
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_when_package_json_is_not_an_object
    FileUtils.touch("package-lock.json")
    File.write("package.json", "null")
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_falls_back_on_malformed_package_json
    FileUtils.touch("package-lock.json")
    File.write("package.json", "{not json")
    assert_equal "npx vite build", RailsVite::Tasks.precompile_command
  end

  def test_precompile_command_ignores_build_script_in_test_env
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: "vite build && vite build --ssr"})
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      assert_equal "npx vite build --mode test", RailsVite::Tasks.precompile_command
    end
  end

  def test_precompile_command_skips_build_script_with_build_mode
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: "vite build && vite build --ssr"})
    with_config(build_mode: "e2e") do
      assert_equal "npx vite build --mode e2e", RailsVite::Tasks.precompile_command
    end
  end

  def test_precompile_command_runs_build_script_without_build_mode
    FileUtils.touch("package-lock.json")
    write_package_json(scripts: {build: "vite build && vite build --ssr"})
    with_config(build_mode: nil) do
      assert_equal "npm run build", RailsVite::Tasks.precompile_command
    end
  end

  def test_build_command_appends_mode_test_in_test_env
    FileUtils.touch("package-lock.json")
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      assert_equal "npx vite build --mode test", RailsVite::Tasks.build_command
    end
  end

  def test_aube_commands
    FileUtils.touch("aube-lock.yaml")
    assert_equal "aube install", RailsVite::Tasks.install_command
    assert_equal "aube add -D vite", RailsVite::Tasks.add_command("vite")
    assert_equal "aube exec vite dev", RailsVite::Tasks.dev_command
    assert_equal "aube exec vite build", RailsVite::Tasks.build_command
  end

  def test_custom_vite_executable_with_aube
    FileUtils.touch("aube-lock.yaml")
    config = RailsVite::Config.new
    config.vite_executable = "vp"

    RailsVite.stub(:config, config) do
      assert_equal "aube exec vp dev", RailsVite::Tasks.dev_command
      assert_equal "aube exec vp build", RailsVite::Tasks.build_command
    end
  end

  def test_custom_vite_executable
    FileUtils.touch("package-lock.json")
    config = RailsVite::Config.new
    config.vite_executable = "vp"

    RailsVite.stub(:config, config) do
      assert_equal "npx vp dev", RailsVite::Tasks.dev_command
      assert_equal "npx vp build", RailsVite::Tasks.build_command
    end
  end

  def test_custom_vite_executable_keeps_the_bun_path
    config = RailsVite::Config.new
    config.vite_executable = "vp"
    exec = {exec: "/apps/my-vite/bin/bun run"}

    RailsVite.stub(:config, config) do
      RailsVite::Tasks.stub(:command_for, ->(key) { exec.fetch(key) }) do
        assert_equal "/apps/my-vite/bin/bun run vp build", RailsVite::Tasks.build_command
      end
    end
  end

  def test_build_command_uses_custom_build_mode
    FileUtils.touch("yarn.lock")
    with_config(build_mode: "e2e") do
      assert_equal "yarn vite build --mode e2e", RailsVite::Tasks.build_command
    end
  end

  def test_build_command_has_no_mode_when_build_mode_is_nil
    FileUtils.touch("yarn.lock")
    with_env("test") do
      with_config(build_mode: nil) do
        assert_equal "yarn vite build", RailsVite::Tasks.build_command
      end
    end
  end

  def test_build_env_sets_build_dir
    assert_equal({"RAILS_VITE_BUILD_DIR" => "vite"}, RailsVite::Tasks.build_env)
  end

  def test_build_env_keeps_test_build_dir_without_mode_test
    with_env("test") do
      with_config(build_mode: nil) do
        assert_equal({"RAILS_VITE_BUILD_DIR" => "vite-test"}, RailsVite::Tasks.build_env)
        assert_equal Rails.root.join("public/vite-test/manifest.json"), RailsVite.config.manifest_path
      end
    end
  end

  def test_build_env_uses_custom_build_dir
    with_config(build_dir: "assets") do
      assert_equal({"RAILS_VITE_BUILD_DIR" => "assets"}, RailsVite::Tasks.build_env)
    end
  end

  def test_build_env_passes_a_string_asset_host
    with_asset_host("https://cdn.example.com") do
      assert_equal "https://cdn.example.com", RailsVite::Tasks.build_env["RAILS_VITE_ASSET_HOST"]
    end
  end

  def test_build_env_skips_a_proc_asset_host
    with_asset_host(->(_source) { "https://cdn.example.com" }) do
      refute RailsVite::Tasks.build_env.key?("RAILS_VITE_ASSET_HOST")
    end
  end

  def test_build_env_skips_a_sharded_asset_host
    with_asset_host("https://assets%d.example.com") do
      refute RailsVite::Tasks.build_env.key?("RAILS_VITE_ASSET_HOST")
    end
  end

  private

  def write_package_json(contents)
    File.write("package.json", JSON.generate(contents))
  end

  def with_env(env, &block)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new(env), &block)
  end

  def with_config(**options, &block)
    config = RailsVite::Config.new
    options.each { |key, value| config.public_send(:"#{key}=", value) }
    RailsVite.stub(:config, config, &block)
  end

  def with_asset_host(asset_host)
    Rails.application.config.action_controller.asset_host = asset_host
    yield
  ensure
    Rails.application.config.action_controller.asset_host = nil
  end
end
