require "find"

module RailsVite
  class AutoBuild
    NEVER = Time.at(0).freeze
    SOURCE_CHECK_INTERVAL = 2 # seconds

    def initialize(app, config)
      @app = app
      @config = config
      @mutex = Mutex.new
      @last_build_at = NEVER
      @cached_source_mtime = nil
      @source_mtime_checked_at = nil
    end

    def call(env)
      build! if stale?
      @app.call(env)
    end

    private

    def build!
      @mutex.synchronize do
        return unless stale?

        Rails.logger.error("rails-vite: build failed") unless system(RailsVite::Tasks.build_command)
        @last_build_at = Time.now
        @cached_source_mtime = nil
        @source_mtime_checked_at = nil
      end
    end

    def stale?
      !File.exist?(@config.manifest_path) ||
        latest_source_mtime > @last_build_at
    end

    def latest_source_mtime
      now = Time.now
      if @cached_source_mtime && @source_mtime_checked_at && (now - @source_mtime_checked_at) < SOURCE_CHECK_INTERVAL
        return @cached_source_mtime
      end

      @source_mtime_checked_at = now
      @cached_source_mtime = compute_latest_source_mtime
    end

    def compute_latest_source_mtime
      latest = NEVER
      source_path = Rails.root.join(@config.source_dir).to_s

      Find.find(source_path) do |path|
        next unless File.file?(path)
        mtime = File.mtime(path)
        latest = mtime if mtime > latest
      end

      latest
    rescue Errno::ENOENT
      Time.now # source dir missing — trigger build to surface the error
    end
  end
end
