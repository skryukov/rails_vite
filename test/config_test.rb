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

  def test_custom_dev_meta_path
    @config.dev_meta_path = Rails.root.join("tmp/custom-vite.json")
    assert_equal Rails.root.join("tmp/custom-vite.json"), @config.dev_meta_path
  end

  def test_custom_manifest_path
    @config.manifest_path = Rails.root.join("public/custom/.vite/manifest.json")
    assert_equal Rails.root.join("public/custom/.vite/manifest.json"), @config.manifest_path
  end

  def test_auto_build_cache_path
    @config.manifest_path = Rails.root.join("public/custom/manifest.json")
    assert_equal Rails.root.join("public/custom/rails-vite-auto-build.json"), @config.auto_build_cache_path
  end

  def test_custom_asset_prefix
    @config.asset_prefix = "/custom"
    assert_equal "/custom", @config.asset_prefix
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

  def test_build_inputs_from_build_meta
    Dir.mktmpdir do |dir|
      vite_dir = File.join(dir, ".vite")
      FileUtils.mkdir_p(vite_dir)
      File.write(File.join(vite_dir, "manifest.json"), "{}")
      File.write(File.join(vite_dir, "rails-vite.json"), '{"buildInputs":["app/frontend/application.ts","/absolute/admin.ts",123]}')

      @config.manifest_path = Pathname.new(File.join(vite_dir, "manifest.json"))

      assert_equal ["app/frontend/application.ts", "/absolute/admin.ts"], @config.build_inputs
    end
  end

  def test_build_inputs_empty_by_default
    assert_equal [], @config.build_inputs
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
end
