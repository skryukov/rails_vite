module RailsVite
  module TagHelper
    CSS_EXTENSIONS = /\.(?:css|scss|sass|less|styl|pcss)\z/

    def vite_tags(*entries, nonce: nil, **options)
      config = RailsVite.config
      resolved = entries.map { |e| resolve_vite_entry(e, config.source_dir) }

      if config.dev_server_running?
        vite_dev_tags(resolved, config.dev_server_url, nonce: nonce, **options)
      else
        vite_prod_tags(resolved, nonce: nonce, **options)
      end
    end
    alias_method :vite_tag, :vite_tags

    def vite_javascript_tag(*entries, **options)
      vite_tags(*entries.map { |e| with_default_ext(e, ".js") }, **options)
    end

    def vite_stylesheet_tag(*entries, **options)
      vite_tags(*entries.map { |e| with_default_ext(e, ".css") }, **options)
    end

    def vite_typescript_tag(*entries, **options)
      vite_tags(*entries.map { |e| with_default_ext(e, ".ts") }, **options)
    end

    def vite_asset_path(name)
      vite_asset_url(RailsVite.manifest.path_for(name))
    end

    def vite_image_tag(name, **options)
      image_tag(vite_asset_path(name), **options)
    end

    private

    def vite_dev_tags(entries, dev_url, nonce: nil, **options)
      tags = []

      unless @_vite_client_emitted
        if RailsVite.config.react_refresh?
          tags << tag.script(type: "module", nonce: nonce) {
            <<~JS.squish.html_safe
              import{injectIntoGlobalHook}from'#{dev_url}/@react-refresh';
              injectIntoGlobalHook(window);
              window.$RefreshReg$=()=>{};
              window.$RefreshSig$=()=>(type)=>type;
            JS
          }
        end
        tags << tag.script(src: "#{dev_url}/@vite/client", type: "module", nonce: nonce)
        @_vite_client_emitted = true
      end

      entries.each do |entry|
        tags << build_asset_tag(entry, "#{dev_url}/#{entry}", nonce: nonce, **options)
      end

      safe_join(tags, "\n")
    end

    def vite_prod_tags(entries, nonce: nil, **options)
      tags = []
      preloaded = Set.new

      entries.each do |entry|
        result = RailsVite.manifest.lookup(entry)

        Array(result[:imports]).each do |import_file|
          next if preloaded.include?(import_file)
          preloaded.add(import_file)
          tags << tag.link(rel: "modulepreload", href: vite_asset_url(import_file), nonce: nonce)
        end

        tags << build_asset_tag(entry, vite_asset_url(result[:file]), nonce: nonce, **options)

        Array(result[:css]).each do |css_file|
          tags << tag.link(rel: "stylesheet", href: vite_asset_url(css_file), nonce: nonce, **options)
        end
      end

      safe_join(tags, "\n")
    end

    def build_asset_tag(entry, url, nonce: nil, **options)
      if css_entry?(entry)
        tag.link(rel: "stylesheet", href: url, nonce: nonce, **options)
      else
        tag.script(src: url, type: "module", nonce: nonce, **options)
      end
    end

    def with_default_ext(name, ext)
      File.extname(name).empty? ? "#{name}#{ext}" : name
    end

    def resolve_vite_entry(entry, source_dir)
      entry.start_with?("#{source_dir}/", "/") ? entry : "#{source_dir}/#{entry}"
    end

    def vite_asset_url(file)
      vite_prefix_asset_host("#{RailsVite.config.asset_prefix}/#{file}")
    end

    def css_entry?(entry)
      CSS_EXTENSIONS.match?(entry)
    end

    def vite_prefix_asset_host(path)
      host = vite_resolve_asset_host
      host ? "#{host}#{path}" : path
    end

    # Memoized per view instance (one per request). Safe for Proc hosts
    # since each request gets a fresh ActionView::Base instance.
    def vite_resolve_asset_host
      return @_vite_asset_host if defined?(@_vite_asset_host)

      @_vite_asset_host = begin
        case (asset_host = Rails.application.config.action_controller.asset_host)
        when String then asset_host.chomp("/")
        when Proc then asset_host.call("")&.chomp("/")
        end
      rescue NoMethodError
        nil
      end
    end
  end
end
