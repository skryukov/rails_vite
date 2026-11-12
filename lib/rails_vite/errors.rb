module RailsVite
  class Error < StandardError; end

  class MissingManifestError < Error
    def initialize(path)
      message = if Rails.env.local?
        "Vite manifest not found at #{path}. Start the Vite dev server with `bin/dev` or precompile assets with `rake vite:build`."
      else
        "Vite manifest not found at #{path}. Run `rake vite:build` to compile assets."
      end
      super(message)
    end
  end

  class BuildError < Error
    # skipped: Vite did not run because these sources already failed to build
    # in an earlier request, so its errors are not in this output.
    def initialize(skipped: false)
      message = if skipped
        "Vite auto build failed earlier for these sources and is not retried until a source changes or the app restarts. Run `rake vite:build` to see its errors."
      else
        "Vite auto build failed; its errors are in the output above. It retries once a source changes, or run `rake vite:build`."
      end
      super(message)
    end
  end

  class MissingEntryError < Error
    def initialize(name, path)
      super("Entry \"#{name}\" not found in Vite manifest at #{path}.")
    end
  end
end
