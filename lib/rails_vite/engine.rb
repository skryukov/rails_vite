module RailsVite
  class Engine < ::Rails::Engine
    initializer "rails_vite.config", before: :load_config_initializers do |app|
      app.config.rails_vite = RailsVite.config
    end

    initializer "rails_vite.auto_build", after: :load_config_initializers do |app|
      vite_config = RailsVite.config
      if RailsVite::AutoBuild.enabled?(vite_config)
        app.middleware.use RailsVite::AutoBuild, vite_config
      end
    end

    initializer "rails_vite.helpers" do
      ActiveSupport.on_load(:action_view) do
        include RailsVite::TagHelper
      end
    end
  end
end
