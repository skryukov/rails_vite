require "shellwords"

module RailsVite
  module Tasks
    extend self

    BUN_CMD = defined?(Bundlebun) ? Bundlebun::Runner.binstub_or_binary_path : "bun"

    COMMANDS = {
      bun: {install: "#{BUN_CMD} install", add: "#{BUN_CMD} add -D", exec: "#{BUN_CMD} run", run: "#{BUN_CMD} run"},
      yarn: {install: "yarn install", add: "yarn add -D", exec: "yarn", run: "yarn run"},
      pnpm: {install: "pnpm install", add: "pnpm add -D", exec: "pnpm", run: "pnpm run"},
      npm: {install: "npm install", add: "npm install -D", exec: "npx", run: "npm run"},
      aube: {install: "aube install", add: "aube add -D", exec: "aube exec", run: "aube run"}
    }.freeze

    LOCKFILES = {
      aube: %w[aube-lock.yaml],
      bun: %w[bun.lockb bun.lock],
      yarn: %w[yarn.lock],
      pnpm: %w[pnpm-lock.yaml],
      npm: %w[package-lock.json]
    }.freeze

    def install_command
      command_for(:install)
    end

    def add_command(*packages)
      "#{command_for(:add)} #{packages.join(" ")}"
    end

    def dev_command
      "#{vite_command} dev"
    end

    def build_command
      cmd = "#{vite_command} build"
      mode = RailsVite.config.build_mode
      cmd += " --mode #{Shellwords.escape(mode)}" if mode
      cmd
    end

    def precompile_command
      return build_command if Rails.env.test? || RailsVite.config.build_mode || !package_json_build_script?
      "#{command_for(:run)} build"
    end

    # Use with build_command. The plugin builds into this dir, so the gem and
    # the plugin use the same dir for all build modes.
    def build_env
      env = {"RAILS_VITE_BUILD_DIR" => RailsVite.config.build_dir}
      asset_host = Rails.application.config.action_controller.asset_host
      env["RAILS_VITE_ASSET_HOST"] = asset_host if asset_host.is_a?(String) && asset_host.present? && !asset_host.include?("%d")
      env
    end

    def tool
      tool_determined_by_lockfile || tool_determined_by_executable
    end

    private

    def vite_command
      "#{command_for(:exec)} #{RailsVite.config.vite_executable}"
    end

    def package_json_build_script?
      path = Rails.root.join("package.json")
      return false unless path.exist?
      package_json = JSON.parse(path.read)
      script = package_json.dig("scripts", "build") if package_json.is_a?(Hash)
      script.is_a?(String) && !script.strip.empty?
    rescue JSON::ParserError, TypeError
      false
    end

    def command_for(key)
      COMMANDS.dig(tool, key) ||
        raise("rails_vite: No suitable JS package manager found for '#{key}'. Ensure npm, yarn, pnpm, bun, or aube is available.")
    end

    def tool_determined_by_lockfile
      LOCKFILES.each do |tool_name, files|
        return tool_name if files.any? { |f| File.exist?(f) }
      end
      nil
    end

    def tool_determined_by_executable
      COMMANDS.each_key do |exe|
        return exe if system "command -v #{exe} > /dev/null"
      end
      nil
    end
  end
end
