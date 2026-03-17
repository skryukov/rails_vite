# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog],
and this project adheres to [Semantic Versioning].

## [0.2.1] - 2026-03-17

### Added

- Vite 8 (Rolldown) compatibility — support `rolldownOptions` alongside `rollupOptions` ([@skryukov])
- Test mode isolation — build to `public/vite-test/` in test mode so test builds don't clobber dev/prod assets ([@skryukov])
- Define `assets:precompile` and `assets:clobber` rake tasks when no asset pipeline is present ([@skryukov])

### Fixed

- Fix `?url` imports and asset references pointing to Rails server instead of Vite dev server ([@skryukov])
- Fix embedded Vite instances (Storybook) overwriting dev stubs in jsbundling mode ([@skryukov])

## [0.2.0] - 2026-03-11

### Added

- jsbundling mode — use Vite as a bundler with `jsbundling-rails` and Propshaft, no gem required ([@skryukov])

### Fixed

- `vite_asset_path` now works in development ([@skryukov])

## [0.1.2] - 2026-03-08

### Fixed

- Short entry names now resolve correctly when using `entrypoints/` directory ([@skryukov])

## [0.1.1] - 2026-03-08

### Added

- Support custom HTML attributes in `vite_tags` (e.g., `data-turbo-track`, `media`) ([@skryukov])
- Add `vite_javascript_tag`, `vite_stylesheet_tag`, and `vite_typescript_tag` compat helpers for easier migration from vite_rails ([@skryukov])
- Auto-discover entrypoints from `sourceDir/entrypoints/` directory ([@skryukov])
- Support extensionless entry names in `vite_tags` (e.g., `vite_tags("application")`) ([@skryukov])
- Subresource Integrity (SRI) support — automatically adds `integrity` and `crossorigin` attributes when `vite-plugin-manifest-sri` is used ([@skryukov])

### Fixed

- `refresh: false` option now correctly disables file watching ([@skryukov])

## [0.1.0] - 2026-03-07

### Added

- Initial release ([@skryukov])

[@skryukov]: https://github.com/skryukov

[Unreleased]: https://github.com/skryukov/rails_vite/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/skryukov/rails_vite/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/skryukov/rails_vite/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/skryukov/rails_vite/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/skryukov/rails_vite/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/skryukov/rails_vite/commits/v0.1.0

[Keep a Changelog]: https://keepachangelog.com/en/1.0.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
