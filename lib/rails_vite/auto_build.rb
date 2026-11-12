require "fileutils"
require "find"

module RailsVite
  class AutoBuild
    NEVER = Time.at(0).freeze
    SOURCE_CHECK_INTERVAL = 2 # seconds

    # Auto build runs when it is on and no dev server serves the assets.
    def self.enabled?(config)
      config.auto_build? && !config.dev_server_running?
    end

    # Builds stale assets outside a request, as the middleware does on the
    # first one; for example, before a test runner starts its workers.
    def self.build_if_stale(config = RailsVite.config)
      new(nil, config).build_if_stale if enabled?(config)
    end

    def initialize(app, config)
      @app = app
      @config = config
      @mutex = Mutex.new
      @cached_source_mtime = nil
      @source_mtime_checked_at = nil
    end

    def call(env)
      build_if_stale
      @app.call(env)
    end

    # Builds the assets when a source is newer than the manifest, or waits for
    # another process's build. Raises BuildError when the build fails.
    def build_if_stale
      # The event also spans waiting for another process's build, so a
      # subscriber sees all the time a request or task spent on auto build.
      ActiveSupport::Notifications.instrument("build.rails_vite") { build! } if stale?
    end

    private

    def build!
      @mutex.synchronize do
        return unless stale?

        with_build_lock do |lock|
          # Another process may have finished a build while this one waited.
          return unless stale?

          sources = compute_latest_source_mtime.to_r.to_s
          raise BuildError.new(skipped: true) if lock.read == "failed #{sources}"

          # Build quietly: vite's per-build summary is noise on every auto-build
          # (e.g. each local system-test run). Warnings and errors still stream.
          built = system(RailsVite::Tasks.build_env, "#{RailsVite::Tasks.build_command} --logLevel warn", chdir: Rails.root)
          lock.rewind
          lock.truncate(0)
          next if built

          # Remember the failure for these sources, so no process rebuilds
          # them until a source changes.
          lock.write("failed #{sources}")
          lock.flush
          raise BuildError
        end
        @cached_source_mtime = nil
        @source_mtime_checked_at = nil
      end
    end

    # Serializes builds across processes (parallel test workers, a server
    # beside a test run): Vite empties the build directory first, so the lock
    # lives outside it. The lock file also records a failed build.
    def with_build_lock
      path = Rails.root.join("tmp", "rails-vite-build-#{@config.build_dir}.lock")
      FileUtils.mkdir_p(path.dirname)
      File.open(path, File::RDWR | File::CREAT, 0o644) do |lock|
        lock.flock(File::LOCK_EX)
        yield lock
      end
    end

    def stale?
      # The manifest file's mtime is our persisted "last build" timestamp: it
      # lives on disk, so freshness survives process restarts (e.g. a new Rails
      # process per local system-test run) without any extra state. A missing
      # manifest is stale, including one another process's build has just
      # removed: Vite empties the build directory first, so it can vanish
      # between any check and the read. Stale takes the build lock, which
      # waits for that build and then checks again.
      latest_source_mtime > File.mtime(@config.manifest_path)
    rescue Errno::ENOENT
      true
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
      source_path = Rails.root.join(@config.source_path).to_s

      Find.find(source_path, *auto_build_path_matches) do |path|
        next unless File.file?(path)
        mtime = File.mtime(path)
        latest = mtime if mtime > latest
      end

      latest
    rescue Errno::ENOENT
      Time.now # source dir missing — trigger build to surface the error
    end

    def auto_build_path_matches
      root = Rails.root.to_s
      @config.auto_build_paths.flat_map do |pattern|
        Dir.glob(pattern.to_s, base: root).filter_map { |match| existing_realpath(match, root) }
      end
    end

    def existing_realpath(path, root)
      File.realpath(path, root)
    rescue SystemCallError
      nil
    end
  end
end
