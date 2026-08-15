module RailsVite
  class Manifest
    NO_MANIFEST_DIGEST = "no-manifest"

    def initialize(path)
      @path = path
    end

    # Vite's default resolve.extensions order, plus CSS extensions
    RESOLVE_EXTENSIONS = %w[.mjs .js .mts .ts .jsx .tsx .json .css .scss .sass .less .styl .pcss].freeze

    def lookup(name)
      manifest = data
      entry = manifest[name] || resolve_with_extension(name, manifest) ||
        raise(MissingEntryError.new(name, @path))

      imports = resolve_imports(entry, Set.new, manifest)
      imported_entries = imports.filter_map { |i| manifest.values.find { |e| e["file"] == i[:file] } }

      {
        file: entry["file"],
        integrity: entry["integrity"],
        css: resolve_css([entry] + imported_entries, manifest),
        imports: imports
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

    def resolve_with_extension(name, manifest)
      return if File.extname(name).present?

      RESOLVE_EXTENSIONS.each do |ext|
        entry = manifest["#{name}#{ext}"]
        return entry if entry
      end
      nil
    end

    def resolve_css(entries, manifest)
      entries.flat_map { |entry| entry.fetch("css", []) }.uniq.map do |css_file|
        integrity = manifest.values.find { |e| e["file"] == css_file }&.dig("integrity")
        {file: css_file, integrity: integrity}
      end
    end

    def resolve_imports(entry, seen, manifest)
      entry.fetch("imports", []).flat_map do |import_key|
        next [] if seen.include?(import_key)
        seen.add(import_key)

        imported = manifest[import_key]
        next [] unless imported

        [{file: imported["file"], integrity: imported["integrity"]}] +
          resolve_imports(imported, seen, manifest)
      end
    end
  end
end
