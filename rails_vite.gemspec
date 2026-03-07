# frozen_string_literal: true

require_relative "lib/rails_vite/version"

Gem::Specification.new do |spec|
  spec.name = "rails_vite"
  spec.version = RailsVite::VERSION
  spec.authors = ["Svyatoslav Kryukov"]
  spec.email = ["me@skryukov.dev"]

  spec.summary = "Vite integration for Rails"
  spec.description = "Simple Vite integration for Rails, inspired by Laravel. No proxy, no config duplication."
  spec.homepage = "https://github.com/skryukov/rails_vite"
  spec.license = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}/blob/main/README.md",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*", "CHANGELOG.md", "LICENSE.txt", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "railties", ">= 7.0"
end
