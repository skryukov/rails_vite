# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog],
and this project adheres to [Semantic Versioning].

## [Unreleased]

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

[Unreleased]: https://github.com/skryukov/rails_vite/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/skryukov/rails_vite/commits/v0.1.0

[Keep a Changelog]: https://keepachangelog.com/en/1.0.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
