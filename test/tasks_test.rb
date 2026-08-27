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

  def test_detects_aube_from_aube_lock
    FileUtils.touch("aube-lock.yaml")
    assert_equal :aube, RailsVite::Tasks.tool
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

  def test_aube_commands
    FileUtils.touch("aube-lock.yaml")
    assert_equal "aube install", RailsVite::Tasks.install_command
    assert_equal "aube add -D vite", RailsVite::Tasks.add_command("vite")
    assert_equal "aube exec vite", RailsVite::Tasks.dev_command
    assert_equal "aube exec vite build", RailsVite::Tasks.build_command
  end
end
