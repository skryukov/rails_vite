# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog],
and this project adheres to [Semantic Versioning].

## Unreleased

### Added

- `refreshDelay` plugin option for `rails()` and `jsbundling()`. It waits the given milliseconds after the last `refresh` change before the full-page reload, and sends one reload for a burst of changes. Use it when Rails sees template changes late, e.g. with `EventedFileUpdateChecker`. Default: `0`, which reloads at once as before (#45) ([@olivier-thatch])
- The install generator sets `"type": "module"` in package.json — Vite and rails-vite-plugin are ESM-only, and without it Node fails to load `vite.config.ts` under npm/pnpm/yarn. When package.json pins another `type`, the generator emits `vite.config.mts` instead (#38) ([@skryukov])
- [aube](https://github.com/aubepkg/aube) package manager support: an `aube-lock.yaml` makes the rake tasks, auto build and the install generator use aube, even next to another lockfile left over from `aube import` (#41) ([@beauraF])
- `config.rails_vite.vite_executable` sets the executable for `rake vite:build`, test builds and auto builds, so Vite-compatible CLIs with another name, such as Vite+'s `vp`, work. The default is `vite` (#42) ([@cole-robertson])
- `auto_build_paths` config option: extra paths and globs, relative to `Rails.root`, that auto build checks for changes besides `sourceDir` (for example `app/views` for Tailwind). It defaults to the root-level Vite, PostCSS, Tailwind and TypeScript configs, `package.json`, and the lockfile, so changes to them now trigger a rebuild (#46) ([@olivier-thatch])
- `config.rails_vite.build_mode` sets the `--mode` for `vite build` in `rake vite:build` and auto builds. The default is unchanged (`"test"` in the test environment, no `--mode` elsewhere); set it to `nil` to pass no `--mode`. The gem now passes its `build_dir` to the plugin in `RAILS_VITE_BUILD_DIR`, so the build directory no longer depends on the mode. Upgrade `rails-vite-plugin` together with the gem: older plugin versions ignore `RAILS_VITE_BUILD_DIR`. With `build_mode` set, `vite:build` runs `vite build --mode` directly instead of the package.json `build` script (#49) ([@olivier-thatch])
- `vite_asset_url(name)` returns a full URL for a Vite asset, like Rails' `asset_url`, for mailers and other places that need an absolute URL (#36) ([@skryukov])

### Changed

- Vite asset URLs are built with Rails' `path_to_asset`, so `asset_host` works as it does for other Rails assets: procs that take the request, `%d` hosts and per-controller hosts. Mailers now use `config.action_mailer.asset_host` (or `config.asset_host`) instead of the controller's. With `relative_url_root`, tags now include the prefix; set Vite's `base` to match (#36) ([@skryukov])
- `rake vite:build` loads the Rails environment first, so `config.rails_vite` settings from initializers (such as `vite_executable`) also apply to it and to `bin/rails test` (#42) ([@cole-robertson])
- The install generator writes `vite dev` instead of `vite` to `Procfile.dev` (#42) ([@cole-robertson])
- `vite:build` (and therefore `assets:precompile`) runs the package.json `build` script when one exists, so `"build": "vite build && vite build --ssr"` produces both client and SSR bundles on deploy. Apps without a `build` script keep the bare `vite build`. If package.json already has a `build` script (e.g. one left over from jsbundling-rails), make sure it builds with Vite before upgrading. Test builds and auto-builds always use the bare command, since their extra flags (`--mode test`, `--logLevel warn`) would only reach the last command of a compound script (#38) ([@skryukov])

### Fixed

- Chunks loaded at runtime (dynamic `import()` and their preloads) now come from a string `config.action_controller.asset_host`, like the tags: `rake vite:build` and auto builds pass it to the plugin in `RAILS_VITE_ASSET_HOST`, which prepends it to Vite's `base`. Set the variable yourself for a proc or `%d` `asset_host`. Needs both the updated gem and plugin (#35) ([@skryukov])
- Allow Vitest's internal Vite server to start in CI. `rails()` and `jsbundling()` now skip the dev-server environment guard and dev server setup under Vitest (#43) ([@cole-robertson])
- Production tags now link the CSS of chunks an entry imports, including nested and shared chunks, not just the entry's own CSS. Chunk CSS comes before the entry's CSS, matching Vite's HTML output, and CSS shared by several entries in one `vite_tags` call is linked once (#40) ([@madogiwa0124])
- Watch the base directories of the `refresh` globs, so template and helper changes trigger a full reload on Linux. Vite's watcher disables globbing, so the globs were watched as literal paths that don't exist. On Linux this also stopped change events for the nested view directories ([@olivier-thatch])
- Ignore a dev metadata file whose Vite process is gone. After a hard kill (SIGKILL, OOM killer), `vite_tags` no longer link to a dead dev server, and Rails started afterwards runs auto builds again. The plugin now records its hostname, and the pid is only checked when Vite runs on the same host, so Vite in another container still counts as running. Needs both the updated gem and plugin (#48) ([@olivier-thatch])

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
[@olivier-thatch]: https://github.com/olivier-thatch
[@beauraF]: https://github.com/beauraF
[@cole-robertson]: https://github.com/cole-robertson
[@madogiwa0124]: https://github.com/madogiwa0124

[Keep a Changelog]: https://keepachangelog.com/en/1.0.0/
[Semantic Versioning]: https://semver.org/spec/v2.0.0.html
