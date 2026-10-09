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

      imports = []
      css = []
      walk_imports(entry, Set.new, manifest, imports, css)
      css.concat(entry.fetch("css", []))

      {
        file: entry["file"],
        integrity: entry["integrity"],
        css: resolve_css(css.uniq, manifest),
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

    def resolve_css(css_files, manifest)
      return [] if css_files.empty?

      by_file = {}
      manifest.each_value { |e| by_file[e["file"]] ||= e }
      css_files.map { |css_file| {file: css_file, integrity: by_file[css_file]&.dig("integrity")} }
    end

    def walk_imports(chunk, seen, manifest, imports, css)
      chunk.fetch("imports", []).each do |import_key|
        next unless seen.add?(import_key)

        imported = manifest[import_key]
        next unless imported

        imports << {file: imported["file"], integrity: imported["integrity"]}
        walk_imports(imported, seen, manifest, imports, css)
        css.concat(imported.fetch("css", []))
      end
    end
  end
end
