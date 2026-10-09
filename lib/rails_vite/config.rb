module RailsVite
  class Config
    META_FILENAME = "rails-vite.json"

    attr_writer :dev_meta_path, :manifest_path, :asset_prefix, :auto_build, :build_dir, :vite_executable, :auto_build_paths, :build_mode

    def dev_meta_path
      @dev_meta_path || Rails.root.join("tmp", META_FILENAME)
    end

    def build_dir
      @build_dir || (Rails.env.test? ? "vite-test" : "vite")
    end

    # The `--mode` for `vite build`. nil or false passes no `--mode`, so Vite uses its default.
    def build_mode
      return @build_mode.presence if defined?(@build_mode)
      "test" if Rails.env.test?
    end

    def vite_executable
      @vite_executable || "vite"
    end

    def manifest_path
      @manifest_path || Rails.root.join("public", build_dir, "manifest.json")
    end

    def asset_prefix
      @asset_prefix || "/#{build_dir}"
    end

    def source_dir
      plugin_meta["sourceDir"] || "app/javascript"
    end

    def entrypoints_dir
      plugin_meta["entrypointsDir"]
    end

    def auto_build?
      return @auto_build if defined?(@auto_build)
      Rails.env.local?
    end

    # Paths or globs relative to Rails.root that auto build checks for changes,
    # in addition to source_dir. Directories are walked recursively.
    def auto_build_paths
      @auto_build_paths ||= [
        "vite.config.*",
        "postcss.config.*",
        "tailwind.config.*",
        "tsconfig*.json",
        "package.json",
        *Tasks::LOCKFILES.values.flatten
      ]
    end

    def dev_server_running?
      return false if Rails.env.test?
      !!dev_server_url
    end

    def dev_server_url
      plugin_meta["url"]
    end

    def ssr_output_dir
      plugin_meta["ssrOutputDir"]
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
      meta = JSON.parse(dev_meta_path.read)
      return meta if dev_server_alive?(meta)

      load_build_meta
    rescue Errno::ENOENT
      load_build_meta
    end

    def load_build_meta
      JSON.parse(manifest_path.dirname.join(META_FILENAME).read)
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    # A hard kill of Vite (SIGKILL, OOM) does not remove the dev meta file.
    # Ignore the file when its process is gone.
    def dev_server_alive?(meta)
      pid = meta["pid"]
      return true unless pid.is_a?(Integer) && pid.positive?
      return true unless meta["hostname"] == Socket.gethostname

      Process.kill(0, pid)
      true
    rescue Errno::EPERM
      true
    rescue Errno::ESRCH
      unless @stale_dev_meta_pid == pid
        @stale_dev_meta_pid = pid
        Rails.logger&.warn("rails-vite: ignoring #{dev_meta_path}, Vite process #{pid} is not running")
      end
      false
    end
  end
end
