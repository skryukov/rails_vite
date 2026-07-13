require "test_helper"

class TasksTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @dir = Dir.mktmpdir
    Dir.chdir(@dir)
  end

  def teardown
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

  def test_bun_lockfile_takes_priority
    FileUtils.touch("bun.lockb")
    FileUtils.touch("yarn.lock")
    assert_equal :bun, RailsVite::Tasks.tool
  end

  def test_install_command
    FileUtils.touch("yarn.lock")
    assert_equal "yarn install", RailsVite::Tasks.install_command
  end

  def test_dev_command
    FileUtils.touch("yarn.lock")
    assert_equal "yarn vite", RailsVite::Tasks.dev_command
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
    assert_equal "npx vite", RailsVite::Tasks.dev_command
    assert_equal "npx vite build", RailsVite::Tasks.build_command
  end

  def test_pnpm_commands
    FileUtils.touch("pnpm-lock.yaml")
    assert_equal "pnpm install", RailsVite::Tasks.install_command
    assert_equal "pnpm add -D vite", RailsVite::Tasks.add_command("vite")
    assert_equal "pnpm vite", RailsVite::Tasks.dev_command
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
     "bun.lock" => "bun run build"}.each do |lockfile, expected|
      FileUtils.touch(lockfile)
      assert_equal expected, RailsVite::Tasks.precompile_command
      FileUtils.rm(lockfile)
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

  def test_build_command_appends_mode_test_in_test_env
    FileUtils.touch("package-lock.json")
    Rails.stub(:env, ActiveSupport::StringInquirer.new("test")) do
      assert_equal "npx vite build --mode test", RailsVite::Tasks.build_command
    end
  end

  private

  def write_package_json(contents)
    File.write("package.json", JSON.generate(contents))
  end
end
