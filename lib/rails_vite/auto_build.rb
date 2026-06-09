require "digest"
require "find"
require "json"
require "pathname"
require "time"

require_relative "version"

module RailsVite
  class AutoBuild
    NEVER = Time.at(0).freeze
    SOURCE_CHECK_INTERVAL = 2 # seconds
    CONFIG_FILES = %w[
      bun.lock
      bun.lockb
      package-lock.json
      package.json
      pnpm-lock.yaml
      tsconfig.json
      vite.config.cjs
      vite.config.cts
      vite.config.js
      vite.config.mjs
      vite.config.mts
      vite.config.ts
      yarn.lock
    ].freeze

    def initialize(app, config)
      @app = app
      @config = config
      @mutex = Mutex.new
      @cached_inputs = nil
      @inputs_checked_at = nil
    end

    def call(env)
      build! if stale?
      @app.call(env)
    end

    private

    def build!
      @mutex.synchronize do
        return unless stale?

        if run_build
          write_metadata(current_digest)
        else
          Rails.logger.error("rails-vite: build failed")
        end

        clear_inputs_cache
      end
    end

    def stale?
      return true unless File.exist?(@config.manifest_path)

      digest = current_digest
      return true unless digest

      metadata = read_metadata
      if metadata.any?
        return !(metadata["success"] == true &&
          metadata["digest"] == digest &&
          metadata["version"] == RailsVite::VERSION)
      end

      latest_input_mtime > File.mtime(@config.manifest_path)
    end

    def run_build
      system(RailsVite::Tasks.build_command)
    end

    def write_metadata(digest)
      return unless digest
      return unless File.exist?(@config.manifest_path)

      @config.auto_build_cache_path.write(JSON.generate({
        success: true,
        digest: digest,
        version: RailsVite::VERSION,
        builtAt: Time.now.utc.iso8601
      }))
    end

    def read_metadata
      JSON.parse(@config.auto_build_cache_path.read)
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def current_digest
      inputs = current_inputs
      return nil if inputs.nil?

      digest = Digest::SHA256.new
      inputs.each do |path|
        digest << path
        digest << "\0"
        digest << File.binread(path)
        digest << "\0"
      end
      digest.hexdigest
    end

    def latest_input_mtime
      inputs = current_inputs
      return Time.now if inputs.nil?

      inputs.map { |path| File.mtime(path) }.max || NEVER
    end

    def current_inputs
      now = Time.now
      if @cached_inputs && @inputs_checked_at && (now - @inputs_checked_at) < SOURCE_CHECK_INTERVAL
        return @cached_inputs
      end

      @inputs_checked_at = now
      @cached_inputs = compute_inputs
    end

    def compute_inputs
      paths = []
      source_path = Rails.root.join(@config.source_dir).to_s

      source_dir_missing = !File.directory?(source_path)
      unless source_dir_missing
        Find.find(source_path) do |path|
          next unless File.file?(path)
          paths << path
        end
      end

      build_input_missing = @config.build_inputs.any? do |path|
        !append_input_path(paths, path)
      end

      CONFIG_FILES.each do |path|
        full_path = Rails.root.join(path).to_s
        paths << full_path if File.file?(full_path)
      end

      return nil if build_input_missing
      return nil if source_dir_missing && @config.build_inputs.empty?

      paths.uniq.sort
    end

    def clear_inputs_cache
      @cached_inputs = nil
      @inputs_checked_at = nil
    end

    def append_input_path(paths, path)
      full_path = expand_input_path(path)
      if File.directory?(full_path)
        Find.find(full_path) do |nested_path|
          next unless File.file?(nested_path)
          paths << nested_path
        end
        true
      elsif File.file?(full_path)
        paths << full_path
        true
      else
        false
      end
    end

    def expand_input_path(path)
      pathname = Pathname.new(path)
      pathname.absolute? ? pathname.to_s : Rails.root.join(path).to_s
    end
  end
end
