require "rails/generators"

module RailsVite
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def install_dependencies
        say "Installing Vite and rails-vite-plugin..."
        run RailsVite::Tasks.add_command("vite", "rails-vite-plugin")
      end

      # Vite and rails-vite-plugin are ESM-only: without `"type": "module"`,
      # Node loads vite.config.ts via require and dies. Package managers
      # create package.json on install but never set the field.
      def ensure_esm_package
        return unless File.exist?("package.json")

        package_json = JSON.parse(File.read("package.json"))
        return if package_json["type"] == "module"

        if package_json.key?("type")
          say %(package.json sets "type": "#{package_json["type"]}", but Vite and rails-vite-plugin are ESM-only — generating vite.config.mts instead.), :yellow
        else
          package_json["type"] = "module"
          File.write("package.json", JSON.pretty_generate(package_json) + "\n")
          say %(Added "type": "module" to package.json (Vite and rails-vite-plugin are ESM-only).)
          warn_about_commonjs_configs
        end
      end

      def create_vite_config
        template "vite.config.ts.tt", esm_package? ? "vite.config.ts" : "vite.config.mts"
      end

      def create_entrypoint
        unless File.exist?("app/javascript/application.js")
          create_file "app/javascript/application.js", "// Entry point for Vite\n"
        end
      end

      def update_gitignore
        return if File.read(".gitignore").include?("public/vite")

        append_to_file ".gitignore", <<~GITIGNORE

          # Vite
          /public/vite
        GITIGNORE
      end

      def update_layout
        layout_path = "app/views/layouts/application.html.erb"
        return unless File.exist?(layout_path)

        gsub_file layout_path,
          /<%=\s*javascript_include_tag\s+["']application["'].*%>/,
          '<%= vite_tags "application" %>'

        gsub_file layout_path,
          /<%=\s*stylesheet_link_tag\s+["']application["'].*%>/,
          '<%= vite_tags "application.css" %>'
      end

      def setup_procfile
        if File.exist?("Procfile.dev")
          unless File.read("Procfile.dev").include?("vite")
            append_to_file "Procfile.dev", "js: #{vite_dev_command}\n"
          end
        else
          template "Procfile.dev.tt", "Procfile.dev"
        end
      end

      def setup_bin_dev
        copy_file "bin/dev", "bin/dev"
        chmod "bin/dev", 0o755
      end

      def done
        say ""
        say "Vite installed! Run `bin/dev` to start development.", :green
      end

      private

      def esm_package?
        File.exist?("package.json") && JSON.parse(File.read("package.json"))["type"] == "module"
      rescue JSON::ParserError
        false
      end

      def warn_about_commonjs_configs
        commonjs_configs = Dir["*.config.js"].select { |f| File.read(f).match?(/\bmodule\.exports\b|\brequire\(/) }
        return if commonjs_configs.empty?

        say "These files use CommonJS and will break under \"type\": \"module\": #{commonjs_configs.join(", ")}. Rename them to .cjs.", :yellow
      end

      def vite_dev_command
        RailsVite::Tasks.dev_command
      end
    end
  end
end
