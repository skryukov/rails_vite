require "json"
require "digest"

require_relative "rails_vite/errors"
require_relative "rails_vite/manifest"
require_relative "rails_vite/config"
require_relative "rails_vite/tasks"
require_relative "rails_vite/tag_helper"
require_relative "rails_vite/auto_build"
require_relative "rails_vite/engine"
require_relative "rails_vite/version"

module RailsVite
  class << self
    def config
      @config ||= Config.new
    end

    def manifest
      @manifest ||= Manifest.new(config.manifest_path)
    end

    def digest
      manifest.digest
    end

    # A Content Security Policy source for the running Vite dev server, e.g.
    #
    #   policy.script_src(*policy.script_src, RailsVite.dev_server_csp_source)
    #   policy.connect_src(*policy.connect_src, RailsVite.dev_server_csp_source(websocket: true))
    #
    # Returns a lambda so the URL is resolved per request: it tracks the dev
    # server's real (possibly auto-incremented) port and contributes nothing
    # when the server isn't running. Pass websocket: true for the HMR socket
    # (http -> ws, https -> wss). RailsVite.config is referenced explicitly
    # because Rails resolves CSP Proc sources via instance_exec, which rebinds
    # self to the controller.
    def dev_server_csp_source(websocket: false)
      -> {
        url = RailsVite.config.dev_server_url
        url && (websocket ? url.sub(/\Ahttp/, "ws") : url)
      }
    end

    def reset!
      @config = nil
      @manifest = nil
    end
  end
end
