namespace :vite do
  desc "Install JavaScript dependencies"
  task :install do
    command = RailsVite::Tasks.install_command
    system(command) || raise("rails_vite: Command install failed, ensure #{command.split.first} is installed")
  end

  desc "Build Vite assets for production"
  task :build do
    command = RailsVite::Tasks.build_command
    system(command) || raise("rails_vite: Command build failed, ensure `#{command}` runs without errors")
  end

  Rake::Task["vite:build"].prereqs << :install unless ENV["SKIP_VITE_INSTALL"]

  desc "Remove Vite build artifacts"
  task :clobber do
    rm_rf Rails.root.join("public", RailsVite.config.asset_prefix.delete_prefix("/"))
  end
end

unless ENV["SKIP_VITE_BUILD"]
  %w[assets:precompile test:prepare spec:prepare db:test:prepare].each do |t|
    Rake::Task[t].enhance(["vite:build"]) if Rake::Task.task_defined?(t)
    break if %w[test:prepare spec:prepare].include?(t) && Rake::Task.task_defined?(t)
  end

  Rake::Task["assets:clobber"].enhance(["vite:clobber"]) if Rake::Task.task_defined?("assets:clobber")
end
