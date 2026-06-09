# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog],
and this project adheres to [Semantic Versioning].

## rails_vite@0.2.3 / rails-vite-plugin@0.2.5 - 2026-06-09

### Added

- `RailsVite.dev_server_csp_source` returns a Content Security Policy source for the running Vite dev server, resolved per request so it tracks the real (possibly auto-incremented) port and adds nothing when the server is down. Pass `websocket: true` for the HMR socket (#25) ([@skryukov])
- `prependSourceDirToEntries` plugin option for `rails()` and `jsbundling()`. Set it to `false` to use Vite's `root` as your `sourceDir` — entries are then resolved by their bare, root-relative names instead of being prefixed with `sourceDir` (#22) ([@skryukov])

### Changed

- Auto builds now run quietly (`vite build --logLevel warn`) to keep system-test output clean; warnings and errors are still shown ([@skryukov])

### Fixed

- The development `@vite/client` and React Fast Refresh tags now derive their nonce from the request (`content_security_policy_nonce`) instead of inheriting whatever nonce the first `vite_*` call passed. A nonce-less first call (e.g. a stylesheet) no longer ships a nonce-less client script under a `strict-dynamic` CSP (#25) ([@skryukov])
- Persist auto-build freshness across process restarts so repeated local system-test runs no longer rebuild unchanged assets. Freshness now derives from the build manifest's timestamp instead of in-memory state (#21) ([@skryukov], [@brodienguyen])
- Don't delete the dev metadata file owned by another Vite process on exit, so concurrent Vite servers no longer clobber each other's dev server info (#27) ([@brodienguyen])
- Allow Vite config to resolve in CI environments without weakening the dev-server environment guard (#28) ([@brodienguyen])

## rails_vite@0.2.2 / rails-vite-plugin@0.2.4 - 2026-04-09

### Added

- Expose SSR output directory configuration ([@skryukov])

## rails-vite-plugin@0.2.3 - 2026-03-27

### Fixed

- Fix double `assets/` prefix in SSR `?url` imports in jsbundling mode ([@skryukov])
- Support glob patterns in input entries ([@skryukov])

## rails-vite-plugin@0.2.2 - 2026-03-17

### Fixed

- Fix ES module identity split when using Propshaft/Sprockets ([@skryukov])

## rails_vite@0.2.1 / rails-vite-plugin@0.2.1 - 2026-03-17

### Added

- Vite 8 (Rolldown) compatibility — support `rolldownOptions` alongside `rollupOptions` ([@skryukov])
- Test mode isolation — build to `public/vite-test/` in test mode so test builds don't clobber dev/prod assets ([@skryukov])
- Define `assets:precompile` and `assets:clobber` rake tasks when no asset pipeline is present ([@skryukov])

### Fixed

- Fix `?url` imports and asset references pointing to Rails server instead of Vite dev server ([@skryukov])
- Fix embedded Vite instances (Storybook) overwriting dev stubs in jsbundling mode ([@skryukov])

## rails_vite@0.2.0 / rails-vite-plugin@0.2.0 - 2026-03-11

### Added

- jsbundling mode — use Vite as a bundler with `jsbundling-rails` and Propshaft, no gem required ([@skryukov])

### Fixed

- `vite_asset_path` now works in development ([@skryukov])

## rails_vite@0.1.2 / rails-vite-plugin@0.1.2 - 2026-03-08

### Fixed

- Short entry names now resolve correctly when using `entrypoints/` directory ([@skryukov])

## rails_vite@0.1.1 / rails-vite-plugin@0.1.1 - 2026-03-08

### Added

- Support custom HTML attributes in `vite_tags` (e.g., `data-turbo-track`, `media`) ([@skryukov])
- Add `vite_javascript_tag`, `vite_stylesheet_tag`, and `vite_typescript_tag` compat helpers for easier migration from vite_rails ([@skryukov])
- Auto-discover entrypoints from `sourceDir/entrypoints/` directory ([@skryukov])
- Support extensionless entry names in `vite_tags` (e.g., `vite_tags("application")`) ([@skryukov])
- Subresource Integrity (SRI) support — automatically adds `integrity` and `crossorigin` attributes when `vite-plugin-manifest-sri` is used ([@skryukov])

### Fixed

- `refresh: false` option now correctly disables file watching ([@skryukov])

## rails_vite@0.1.0 / rails-vite-plugin@0.1.0 - 2026-03-07

### Added

- Initial release ([@skryukov])

[@skryukov]: https://github.com/skryukov
[@brodienguyen]: https://github.com/brodienguyen

[Keep a Changelog]: https://keepachangelog.com/en/1.0.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
