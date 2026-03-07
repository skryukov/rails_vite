require "test_helper"

class ManifestTest < Minitest::Test
  SAMPLE_MANIFEST = {
    "app/javascript/application.js" => {
      "file" => "assets/application-a1b2c3d4.js",
      "isEntry" => true,
      "css" => ["assets/application-x9y8z7w6.css"],
      "imports" => ["_vendor-b3c4d5e6"]
    },
    "_vendor-b3c4d5e6" => {
      "file" => "assets/vendor-b3c4d5e6.js",
      "imports" => ["_shared-1234abcd"]
    },
    "_shared-1234abcd" => {
      "file" => "assets/shared-1234abcd.js"
    },
    "app/javascript/admin.css" => {
      "file" => "assets/admin-deadbeef.css",
      "isEntry" => true
    },
    "app/assets/images/logo.png" => {
      "file" => "assets/logo-aabbccdd.png"
    }
  }.freeze

  def setup
    @dir = Dir.mktmpdir
    @manifest_path = File.join(@dir, "manifest.json")
    File.write(@manifest_path, JSON.generate(SAMPLE_MANIFEST))
    @manifest = RailsVite::Manifest.new(@manifest_path)
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_lookup_entry
    result = @manifest.lookup("app/javascript/application.js")

    assert_equal "assets/application-a1b2c3d4.js", result[:file]
    assert_equal ["assets/application-x9y8z7w6.css"], result[:css]
    assert_includes result[:imports], "assets/vendor-b3c4d5e6.js"
  end

  def test_lookup_resolves_nested_imports
    result = @manifest.lookup("app/javascript/application.js")

    assert_includes result[:imports], "assets/vendor-b3c4d5e6.js"
    assert_includes result[:imports], "assets/shared-1234abcd.js"
  end

  def test_lookup_css_entry
    result = @manifest.lookup("app/javascript/admin.css")

    assert_equal "assets/admin-deadbeef.css", result[:file]
    assert_empty result[:css]
    assert_empty result[:imports]
  end

  def test_lookup_image_asset
    path = @manifest.path_for("app/assets/images/logo.png")

    assert_equal "assets/logo-aabbccdd.png", path
  end

  def test_missing_entry_raises
    error = assert_raises(RailsVite::MissingEntryError) do
      @manifest.lookup("nonexistent.js")
    end

    assert_match "nonexistent.js", error.message
  end

  def test_missing_manifest_raises
    manifest = RailsVite::Manifest.new("/nonexistent/manifest.json")

    error = assert_raises(RailsVite::MissingManifestError) do
      manifest.lookup("anything")
    end

    assert_match "manifest not found", error.message.downcase
  end

  def test_circular_imports_dont_loop
    circular = {
      "entry.js" => {
        "file" => "assets/entry.js",
        "imports" => ["_a"]
      },
      "_a" => {
        "file" => "assets/a.js",
        "imports" => ["_b"]
      },
      "_b" => {
        "file" => "assets/b.js",
        "imports" => ["_a"]
      }
    }

    File.write(@manifest_path, JSON.generate(circular))
    manifest = RailsVite::Manifest.new(@manifest_path)

    result = manifest.lookup("entry.js")
    assert_equal ["assets/a.js", "assets/b.js"], result[:imports]
  end

  def test_digest_returns_hex_string
    digest = @manifest.digest
    assert_match(/\A[0-9a-f]{32}\z/, digest)
  end

  def test_digest_returns_no_manifest_when_missing
    manifest = RailsVite::Manifest.new("/nonexistent/manifest.json")
    assert_equal "no-manifest", manifest.digest
  end

  def test_data_reloads_in_local_environment
    # Rails.env is "test" which is local?, so manifest reloads each time
    assert Rails.env.local?, "Expected test env to be local"

    result1 = @manifest.lookup("app/javascript/application.js")
    assert_equal "assets/application-a1b2c3d4.js", result1[:file]

    updated = SAMPLE_MANIFEST.merge(
      "app/javascript/application.js" => {
        "file" => "assets/application-updated.js",
        "isEntry" => true,
        "css" => [],
        "imports" => []
      }
    )
    File.write(@manifest_path, JSON.generate(updated))

    result2 = @manifest.lookup("app/javascript/application.js")
    assert_equal "assets/application-updated.js", result2[:file]
  end
end
