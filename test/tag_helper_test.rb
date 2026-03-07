require "test_helper"

class TagHelperTest < Minitest::Test
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::AssetTagHelper
  include RailsVite::TagHelper

  SAMPLE_MANIFEST = {
    "app/javascript/application.js" => {
      "file" => "assets/application-a1b2c3d4.js",
      "isEntry" => true,
      "css" => ["assets/application-x9y8z7w6.css"],
      "imports" => ["_vendor-b3c4d5e6"]
    },
    "_vendor-b3c4d5e6" => {
      "file" => "assets/vendor-b3c4d5e6.js"
    },
    "app/javascript/admin.js" => {
      "file" => "assets/admin-deadbeef.js",
      "isEntry" => true,
      "css" => [],
      "imports" => []
    },
    "app/javascript/admin.css" => {
      "file" => "assets/admin-aabb1122.css",
      "isEntry" => true
    },
    "app/assets/images/logo.png" => {
      "file" => "assets/logo-aabbccdd.png"
    }
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    @vite_dir = File.join(@dir, "vite")
    FileUtils.mkdir_p(@vite_dir)
    @manifest_path = File.join(@vite_dir, "manifest.json")
    File.write(@manifest_path, JSON.generate(SAMPLE_MANIFEST))

    RailsVite.reset!
    config = RailsVite.config
    config.manifest_path = Pathname.new(@manifest_path)
    config.dev_meta_path = Pathname.new(File.join(@dir, "rails-vite.json"))

    @_vite_client_emitted = nil
    remove_instance_variable(:@_vite_asset_host) if defined?(@_vite_asset_host)
  end

  def teardown
    FileUtils.rm_rf(@dir)
    RailsVite.reset!
  end

  # Production mode tests

  def test_vite_tags_production
    html = vite_tags("app/javascript/application.js")

    assert_match %r{rel="modulepreload".*href="/vite/assets/vendor-b3c4d5e6.js"}, html
    assert_match %r{<script.*src="/vite/assets/application-a1b2c3d4.js".*type="module"}, html
    assert_match %r{rel="stylesheet".*href="/vite/assets/application-x9y8z7w6.css"}, html
  end

  def test_vite_tags_production_with_nonce
    html = vite_tags("app/javascript/application.js", nonce: "abc123")

    assert_match(/nonce="abc123"/, html)
  end

  def test_vite_tags_css_entry
    html = vite_tags("app/javascript/admin.css")

    assert_match %r{href="/vite/assets/admin-aabb1122.css"}, html
    assert_match %r{rel="stylesheet"}, html
    refute_match %r{type="module"}, html
  end

  def test_vite_tags_multiple_entries
    html = vite_tags("app/javascript/application.js", "app/javascript/admin.js")

    assert_match %r{application-a1b2c3d4\.js}, html
    assert_match %r{admin-deadbeef\.js}, html
  end

  def test_vite_asset_path
    path = vite_asset_path("app/assets/images/logo.png")

    assert_equal "/vite/assets/logo-aabbccdd.png", path
  end

  # Dev mode tests

  def test_vite_tags_dev_mode
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html = vite_tags("app/javascript/application.js")

    assert_match %r{src="http://localhost:5173/@vite/client"}, html
    assert_match %r{src="http://localhost:5173/app/javascript/application.js"}, html
  end

  def test_vite_tags_dev_mode_deduplicates_client
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html1 = vite_tags("app/javascript/application.js")
    html2 = vite_tags("app/javascript/admin.js")

    assert_match %r{@vite/client}, html1
    refute_match %r{@vite/client}, html2
  end

  def test_vite_tags_dev_css_entry
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html = vite_tags("app/javascript/admin.css")

    assert_match %r{href="http://localhost:5173/app/javascript/admin.css"}, html
    assert_match %r{@vite/client}, html
  end

  # Asset host tests

  def test_vite_asset_path_with_asset_host
    Rails.application.config.action_controller.asset_host = "https://cdn.example.com"

    path = vite_asset_path("app/assets/images/logo.png")

    assert_equal "https://cdn.example.com/vite/assets/logo-aabbccdd.png", path
  ensure
    Rails.application.config.action_controller.asset_host = nil
  end

  def test_vite_tags_production_with_asset_host
    Rails.application.config.action_controller.asset_host = "https://cdn.example.com"

    html = vite_tags("app/javascript/application.js")

    assert_match %r{src="https://cdn\.example\.com/vite/assets/application-a1b2c3d4\.js"}, html
    assert_match %r{href="https://cdn\.example\.com/vite/assets/application-x9y8z7w6\.css"}, html
  ensure
    Rails.application.config.action_controller.asset_host = nil
  end

  # sourceDir short name tests

  def test_vite_tags_short_name_production
    html = vite_tags("application.js")

    assert_match %r{src="/vite/assets/application-a1b2c3d4.js"}, html
    assert_match %r{rel="stylesheet".*href="/vite/assets/application-x9y8z7w6.css"}, html
  end

  def test_vite_tags_extensionless_production
    html = vite_tags("application")

    assert_match %r{src="/vite/assets/application-a1b2c3d4.js"}, html
    assert_match %r{rel="stylesheet".*href="/vite/assets/application-x9y8z7w6.css"}, html
  end

  def test_vite_tags_short_name_dev_mode
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html = vite_tags("application.js")

    assert_match %r{src="http://localhost:5173/app/javascript/application.js"}, html
  end

  def test_vite_tags_short_name_custom_source_dir
    File.write(File.join(File.dirname(@manifest_path), "rails-vite.json"), '{"sourceDir":"app/frontend"}')

    custom_manifest = SAMPLE_MANIFEST.merge(
      "app/frontend/application.js" => {
        "file" => "assets/application-custom.js",
        "isEntry" => true,
        "css" => [],
        "imports" => []
      }
    )
    File.write(@manifest_path, JSON.generate(custom_manifest))

    html = vite_tags("application.js")

    assert_match %r{src="/vite/assets/application-custom.js"}, html
  end

  def test_vite_tags_full_path_not_prefixed
    html = vite_tags("app/javascript/application.js")

    assert_match %r{src="/vite/assets/application-a1b2c3d4.js"}, html
  end

  def test_vite_tags_relative_path_within_source_dir
    File.write(File.join(File.dirname(@manifest_path), "rails-vite.json"), '{"sourceDir":"app/frontend"}')

    custom_manifest = SAMPLE_MANIFEST.merge(
      "app/frontend/entrypoints/app.js" => {
        "file" => "assets/app-rel123.js",
        "isEntry" => true,
        "css" => [],
        "imports" => []
      }
    )
    File.write(@manifest_path, JSON.generate(custom_manifest))

    html = vite_tags("entrypoints/app.js")

    assert_match %r{src="/vite/assets/app-rel123.js"}, html
  end

  # React refresh preamble tests

  def test_vite_tags_dev_mode_with_react_refresh
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript","reactRefresh":true}')

    html = vite_tags("app/javascript/application.js")

    assert_match %r{@react-refresh}, html
    assert_match %r{injectIntoGlobalHook}, html
    assert_match %r{@vite/client}, html
  end

  def test_vite_tags_dev_mode_without_react_refresh
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html = vite_tags("app/javascript/application.js")

    refute_match %r{@react-refresh}, html
    assert_match %r{@vite/client}, html
  end

  def test_vite_tags_dev_react_preamble_before_client
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript","reactRefresh":true}')

    html = vite_tags("app/javascript/application.js")

    preamble_pos = html.index("@react-refresh")
    client_pos = html.index("@vite/client")
    assert preamble_pos < client_pos, "React refresh preamble should appear before @vite/client"
  end

  def test_vite_tags_prod_no_react_preamble
    html = vite_tags("app/javascript/application.js")

    refute_match %r{@react-refresh}, html
  end

  # vite_image_tag tests

  def test_vite_image_tag
    html = vite_image_tag("app/assets/images/logo.png", alt: "Logo")

    assert_match %r{<img.*src="/vite/assets/logo-aabbccdd.png"}, html
    assert_match %r{alt="Logo"}, html
  end

  # Dev mode nonce tests

  def test_vite_tags_dev_mode_with_nonce
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html = vite_tags("app/javascript/application.js", nonce: "dev123")

    assert_match %r{@vite/client.*nonce="dev123"}, html
    assert_match %r{application.js.*nonce="dev123"}, html
  end

  # Proc asset host tests

  def test_vite_asset_path_with_proc_asset_host
    Rails.application.config.action_controller.asset_host = ->(_source) { "https://lambda-cdn.example.com" }

    path = vite_asset_path("app/assets/images/logo.png")

    assert_equal "https://lambda-cdn.example.com/vite/assets/logo-aabbccdd.png", path
  ensure
    Rails.application.config.action_controller.asset_host = nil
  end

  # CSS extension tests

  def test_css_extensions_recognized
    %w[style.css style.scss style.sass style.less style.styl style.pcss].each do |entry|
      assert css_entry?(entry), "Expected #{entry} to be recognized as CSS"
    end
  end

  def test_js_not_recognized_as_css
    refute css_entry?("app.js")
    refute css_entry?("app.ts")
  end

  # Dedup modulepreload tests

  def test_vite_tags_dedup_shared_imports
    shared_manifest = SAMPLE_MANIFEST.merge(
      "app/javascript/admin.js" => {
        "file" => "assets/admin-deadbeef.js",
        "isEntry" => true,
        "css" => [],
        "imports" => ["_vendor-b3c4d5e6"]
      }
    )
    File.write(@manifest_path, JSON.generate(shared_manifest))

    html = vite_tags("app/javascript/application.js", "app/javascript/admin.js")

    vendor_preloads = html.scan(%r{rel="modulepreload".*?href="/vite/assets/vendor-b3c4d5e6.js"})
    assert_equal 1, vendor_preloads.size, "Shared import should only be preloaded once"
  end

  # Custom HTML attributes tests

  def test_vite_tags_production_with_custom_attributes
    html = vite_tags("app/javascript/application.js", "data-turbo-track": "reload")

    assert_match %r{<script.*data-turbo-track="reload"}, html
    assert_match %r{rel="stylesheet".*data-turbo-track="reload"}, html
  end

  def test_vite_tags_css_entry_with_custom_attributes
    html = vite_tags("app/javascript/admin.css", media: "all", "data-turbo-track": "reload")

    assert_match %r{media="all"}, html
    assert_match %r{data-turbo-track="reload"}, html
  end

  def test_vite_tags_dev_mode_with_custom_attributes
    File.write(File.join(@dir, "rails-vite.json"), '{"url":"http://localhost:5173","sourceDir":"app/javascript"}')

    html = vite_tags("app/javascript/application.js", "data-turbo-track": "reload")

    assert_match %r{src="http://localhost:5173/app/javascript/application.js".*data-turbo-track="reload"}, html
  end

  # SRI tests

  def test_vite_tags_production_with_sri
    sri_manifest = {
      "app/javascript/application.js" => {
        "file" => "assets/application-a1b2c3d4.js",
        "isEntry" => true,
        "integrity" => "sha384-abc123",
        "css" => ["assets/application-x9y8z7w6.css"],
        "imports" => ["_vendor-b3c4d5e6"]
      },
      "app/javascript/application-x9y8z7w6.css" => {
        "file" => "assets/application-x9y8z7w6.css",
        "integrity" => "sha384-css456"
      },
      "_vendor-b3c4d5e6" => {
        "file" => "assets/vendor-b3c4d5e6.js",
        "integrity" => "sha384-vendor789"
      }
    }
    File.write(@manifest_path, JSON.generate(sri_manifest))

    html = vite_tags("app/javascript/application.js")

    assert_match %r{integrity="sha384-abc123"}, html
    assert_match %r{crossorigin="anonymous"}, html
    assert_match %r{rel="modulepreload".*integrity="sha384-vendor789"}, html
    assert_match %r{rel="stylesheet".*integrity="sha384-css456"}, html
  end

  def test_vite_tags_production_no_sri_when_absent
    html = vite_tags("app/javascript/application.js")

    refute_match %r{integrity=}, html
    refute_match %r{crossorigin=}, html
  end

  # Error tests

  def test_missing_entry_raises
    assert_raises(RailsVite::MissingEntryError) do
      vite_tags("nonexistent.js")
    end
  end

  def test_missing_manifest_raises
    FileUtils.rm(@manifest_path)

    assert_raises(RailsVite::MissingManifestError) do
      vite_tags("app/javascript/application.js")
    end
  end
end
