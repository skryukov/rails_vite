module RailsVite
  module Tasks
    extend self

    BUN_CMD = defined?(Bundlebun) ? Bundlebun::Runner.binstub_or_binary_path : "bun"

    COMMANDS = {
      bun: {install: "#{BUN_CMD} install", add: "#{BUN_CMD} add -D", dev: "#{BUN_CMD} run vite", build: "#{BUN_CMD} run vite build"},
      yarn: {install: "yarn install", add: "yarn add -D", dev: "yarn vite", build: "yarn vite build"},
      pnpm: {install: "pnpm install", add: "pnpm add -D", dev: "pnpm vite", build: "pnpm vite build"},
      npm: {install: "npm install", add: "npm install -D", dev: "npx vite", build: "npx vite build"}
    }.freeze

    LOCKFILES = {
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
      vite_command_for(:dev)
    end

    def build_command
      cmd = vite_command_for(:build)
      cmd += " --mode test" if Rails.env.test?
      cmd
    end

    def tool
      tool_determined_by_lockfile || tool_determined_by_executable
    end

    private

    def vite_command_for(key)
      command_for(key).sub(/\bvite\b/) { RailsVite.config.vite_executable }
    end

    def command_for(key)
      COMMANDS.dig(tool, key) ||
        raise("rails_vite: No suitable JS package manager found for '#{key}'. Ensure npm, yarn, pnpm, or bun is available.")
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
