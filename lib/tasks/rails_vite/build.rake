namespace :vite do
  desc "Install JavaScript dependencies"
  task :install do
    command = RailsVite::Tasks.install_command
    system(command) || raise("rails_vite: Command install failed, ensure #{command.split.first} is installed")
  end

  desc "Build Vite assets for production"
  task :build do
    command = RailsVite::Tasks.precompile_command
    system(command) || raise("rails_vite: Command build failed, ensure `#{command}` runs without errors")
  end

  Rake::Task["vite:build"].prereqs << :install unless ENV["SKIP_VITE_INSTALL"]

  desc "Remove Vite build artifacts"
  task :clobber do
    rm_rf Rails.root.join("public", RailsVite.config.asset_prefix.delete_prefix("/"))
  end
end

unless ENV["SKIP_VITE_BUILD"]
  if Rake::Task.task_defined?("assets:precompile")
    Rake::Task["assets:precompile"].enhance(["vite:build"])
  else
    desc "Compile assets"
    Rake::Task.define_task("assets:precompile" => "vite:build")
  end

  if Rake::Task.task_defined?("assets:clobber")
    Rake::Task["assets:clobber"].enhance(["vite:clobber"])
  else
    desc "Remove compiled assets"
    Rake::Task.define_task("assets:clobber" => "vite:clobber")
  end

  %w[test:prepare spec:prepare db:test:prepare].each do |t|
    if Rake::Task.task_defined?(t)
      Rake::Task[t].enhance(["vite:build"])
      break
    end
  end
end
