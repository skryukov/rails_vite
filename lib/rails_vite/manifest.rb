module RailsVite
  class Manifest
    NO_MANIFEST_DIGEST = "no-manifest"

    def initialize(path)
      @path = path
    end

    def lookup(name)
      manifest = data
      entry = manifest[name] || raise(MissingEntryError.new(name, @path))

      {
        file: entry["file"],
        css: entry.fetch("css", []),
        imports: resolve_imports(entry, Set.new, manifest)
      }
    end

    def path_for(name)
      lookup(name)[:file]
    end

    def digest
      Digest::MD5.file(@path).hexdigest
    rescue Errno::ENOENT
      NO_MANIFEST_DIGEST
    end

    private

    def data
      if Rails.env.local?
        load_manifest
      else
        @data ||= load_manifest
      end
    end

    def load_manifest
      JSON.parse(File.read(@path))
    rescue Errno::ENOENT
      raise MissingManifestError.new(@path)
    end

    def resolve_imports(entry, seen, manifest)
      entry.fetch("imports", []).flat_map do |import_key|
        next [] if seen.include?(import_key)
        seen.add(import_key)

        imported = manifest[import_key]
        next [] unless imported

        [imported["file"]] + resolve_imports(imported, seen, manifest)
      end
    end
  end
end
