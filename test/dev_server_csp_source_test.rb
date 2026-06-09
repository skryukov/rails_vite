require "test_helper"
require "action_dispatch/http/content_security_policy"

class DevServerCspSourceTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
    RailsVite.reset!
    config = RailsVite.config
    config.manifest_path = Pathname.new(File.join(@dir, "vite", "manifest.json"))
    config.dev_meta_path = Pathname.new(File.join(@dir, "rails-vite.json"))
  end

  def teardown
    FileUtils.rm_rf(@dir)
    RailsVite.reset!
  end

  def write_meta(url)
    File.write(File.join(@dir, "rails-vite.json"), JSON.generate("url" => url, "sourceDir" => "app/javascript"))
  end

  def test_returns_dev_server_url_when_running
    write_meta("http://localhost:5199")

    assert_equal "http://localhost:5199", RailsVite.dev_server_csp_source.call
  end

  def test_websocket_transforms_http_to_ws
    write_meta("http://localhost:5199")

    assert_equal "ws://localhost:5199", RailsVite.dev_server_csp_source(websocket: true).call
  end

  def test_websocket_transforms_https_to_wss
    write_meta("https://localhost:5173")

    assert_equal "wss://localhost:5173", RailsVite.dev_server_csp_source(websocket: true).call
  end

  def test_nil_when_server_down
    assert_nil RailsVite.dev_server_csp_source.call
    assert_nil RailsVite.dev_server_csp_source(websocket: true).call
  end

  def test_resolves_in_real_csp_build_and_survives_self_rebinding
    write_meta("http://localhost:5199")

    policy = ActionDispatch::ContentSecurityPolicy.new do |p|
      p.script_src(*p.script_src, "'self'", RailsVite.dev_server_csp_source)
      p.connect_src(*p.connect_src, "'self'", RailsVite.dev_server_csp_source(websocket: true))
    end

    # Rails resolves Proc sources via context.instance_exec(&source), rebinding
    # self to the controller. trap_context.config raises, so a helper calling a
    # bare `config` instead of RailsVite.config would fail here.
    trap_context = Object.new
    def trap_context.config
      raise "lambda resolved against the wrong self"
    end

    built = policy.build(trap_context)

    assert_includes built, "script-src 'self' http://localhost:5199"
    assert_includes built, "connect-src 'self' ws://localhost:5199"
  end

  def test_real_csp_build_drops_source_when_server_down
    policy = ActionDispatch::ContentSecurityPolicy.new do |p|
      p.script_src(*p.script_src, "'self'", RailsVite.dev_server_csp_source)
    end

    assert_equal "script-src 'self'", policy.build(Object.new)
  end
end
