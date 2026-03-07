module RailsVite
  class Config
    META_FILENAME = "rails-vite.json"

    attr_writer :dev_meta_path, :manifest_path, :asset_prefix, :auto_build

    def dev_meta_path
      @dev_meta_path || Rails.root.join("tmp", META_FILENAME)
    end

    def manifest_path
      @manifest_path || Rails.root.join("public/vite/manifest.json")
    end

    def asset_prefix
      @asset_prefix || "/vite"
    end

    def source_dir
      plugin_meta["sourceDir"] || "app/javascript"
    end

    def auto_build?
      return @auto_build if defined?(@auto_build)
      Rails.env.local?
    end

    def dev_server_running?
      !!dev_server_url
    end

    def dev_server_url
      plugin_meta["url"]
    end

    def react_refresh?
      plugin_meta["reactRefresh"] == true
    end

    private

    def plugin_meta
      if Rails.env.local?
        load_plugin_meta
      else
        @plugin_meta ||= load_plugin_meta
      end
    end

    def load_plugin_meta
      JSON.parse(dev_meta_path.read)
    rescue Errno::ENOENT
      build_meta_path = manifest_path.dirname.join(META_FILENAME)
      begin
        JSON.parse(build_meta_path.read)
      rescue Errno::ENOENT, JSON::ParserError
        {}
      end
    end
  end
end
