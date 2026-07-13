require "test_helper"
require "generators/rails_vite/install/install_generator"

class InstallGeneratorEsmTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @dir = Dir.mktmpdir
    Dir.chdir(@dir)
    @generator = RailsVite::Generators::InstallGenerator.new
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@dir)
  end

  def test_adds_type_module_when_missing
    File.write("package.json", JSON.pretty_generate({"devDependencies" => {"vite" => "^8.0.0"}}))

    capture_io { @generator.ensure_esm_package }

    parsed = JSON.parse(File.read("package.json"))
    assert_equal "module", parsed["type"]
    assert_equal({"vite" => "^8.0.0"}, parsed["devDependencies"])
  end

  def test_keeps_package_json_untouched_when_already_esm
    File.write("package.json", %({"type":"module"}))

    capture_io { @generator.ensure_esm_package }

    assert_equal %({"type":"module"}), File.read("package.json")
  end

  def test_leaves_explicit_commonjs_alone_and_warns
    File.write("package.json", %({"type":"commonjs"}))

    out, _err = capture_io { @generator.ensure_esm_package }

    assert_equal "commonjs", JSON.parse(File.read("package.json"))["type"]
    assert_match(/ESM-only/, out)
  end

  def test_skips_when_package_json_is_missing
    capture_io { @generator.ensure_esm_package }

    refute File.exist?("package.json")
  end

  def test_warns_about_commonjs_config_files
    File.write("package.json", "{}")
    File.write("postcss.config.js", "module.exports = {}\n")

    out, _err = capture_io { @generator.ensure_esm_package }

    assert_match(/postcss\.config\.js/, out)
  end

  def test_does_not_warn_about_esm_config_files
    File.write("package.json", "{}")
    File.write("postcss.config.js", "export default {}\n")

    out, _err = capture_io { @generator.ensure_esm_package }

    refute_match(/postcss\.config\.js/, out)
  end
end
