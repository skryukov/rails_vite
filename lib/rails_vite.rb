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

    def reset!
      @config = nil
      @manifest = nil
    end
  end
end
