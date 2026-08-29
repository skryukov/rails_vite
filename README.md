# RailsVite

[![Gem Version](https://badge.fury.io/rb/rails_vite.svg)](https://rubygems.org/gems/rails_vite)

Vite integration for Rails, inspired by [Laravel's Vite plugin](https://laravel.com/docs/12.x/vite). No proxy, no config duplication, no magic.

## Table of Contents

- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Vite Config](#vite-config)
- [Adding Frameworks](#adding-frameworks)
- [SSR](#ssr)
- [Auto Build](#auto-build)
- [Testing the Build](#testing-the-build)
- [Custom Paths](#custom-paths)
- [Rake Tasks](#rake-tasks)
- [jsbundling Mode](#jsbundling-mode)
- [Migrating from vite_rails](#migrating-from-vite_rails)
- [Contributing](#contributing)
- [License](#license)

<a href="https://evilmartians.com/?utm_source=rails_vite&utm_campaign=project_page">
<img src="https://evilmartians.com/badges/sponsored-by-evil-martians.svg" alt="Built by Evil Martians" width="236" height="54">
</a>

## How It Works

**Development:** The Vite plugin writes `tmp/rails-vite.json` with the dev server URL. The Rails helper reads it and emits `<script>` tags pointing directly at Vite. The browser talks to Vite — Puma never touches your assets.

**Production:** `vite build` outputs fingerprinted assets to `public/vite/` with a standard Vite manifest. The Rails helper reads the manifest and emits the correct tags.

No Rack proxy. No `config/vite.json`. No extra binstubs.

## Quick Start

Add to your Gemfile:

```ruby
gem "rails_vite"
```

Run the install generator:

```bash
bundle install
bin/rails generate rails_vite:install
```

This creates `vite.config.ts`, installs dependencies, and updates your layout.

Start development:

```bash
bin/dev
```

## Usage

In your layout:

```erb
<%= vite_tags "application.js" %>
```

Short names are automatically prefixed with `sourceDir` (default: `app/javascript`). Paths containing `/` are used as-is.

**Development output** (when `tmp/rails-vite.json` exists):

```html
<script src="http://localhost:5173/@vite/client" type="module"></script>
<script src="http://localhost:5173/app/javascript/application.js" type="module"></script>
```

**Production output** (reads manifest):

```html
<link rel="modulepreload" href="/vite/assets/vendor-b3c4d5e6.js" />
<script src="/vite/assets/application-a1b2c3d4.js" type="module"></script>
<link rel="stylesheet" href="/vite/assets/application-x9y8z7w6.css" />
```

### Helpers

| Helper | Purpose |
|--------|---------|
| `vite_tags(*entries, **options)` | Emits script, stylesheet, and modulepreload tags |
| `vite_javascript_tag(*entries, **options)` | Same as `vite_tags`, appends `.js` to extensionless names |
| `vite_stylesheet_tag(*entries, **options)` | Same as `vite_tags`, appends `.css` to extensionless names |
| `vite_typescript_tag(*entries, **options)` | Same as `vite_tags`, appends `.ts` to extensionless names |
| `vite_asset_path(name)` | Returns the fingerprinted path from the manifest |
| `vite_image_tag(name, **options)` | Image tag with manifest-resolved src |

All tag helpers accept arbitrary HTML attributes:

```erb
<%= vite_tags "application.js", "application.css",
    "data-turbo-track": "reload", nonce: content_security_policy_nonce %>
```

### CSS Entry Points

CSS files are detected by extension and emit `<link rel="stylesheet">`:

```erb
<%= vite_tags "application.css" %>
```

### Content Security Policy

Pass a `nonce` to any tag helper; it's applied to every tag it emits:

```erb
<%= vite_tags "application.js", nonce: content_security_policy_nonce %>
```

The dev server's `@vite/client` and React Fast Refresh tags pick up the request nonce automatically, so they work under `strict-dynamic` even when your first `vite_*` call is a nonce-less stylesheet.

Running a CSP in development? Allow the dev server's origin with `RailsVite.dev_server_csp_source` — it resolves per request, so it tracks Vite's actual port and adds nothing when the server is down:

```ruby
# config/initializers/content_security_policy.rb — inside your `policy` block
if Rails.env.development?
  policy.script_src(*policy.script_src, RailsVite.dev_server_csp_source)
  policy.style_src(*policy.style_src, RailsVite.dev_server_csp_source)
  policy.connect_src(*policy.connect_src, RailsVite.dev_server_csp_source(websocket: true)) # HMR
end
```

### Subresource Integrity (SRI)

[SRI](https://developer.mozilla.org/en-US/docs/Web/Security/Subresource_Integrity) lets browsers verify that fetched assets haven't been tampered with by checking cryptographic hashes. Install the [`vite-plugin-manifest-sri`](https://github.com/nicolo-ribaudo/vite-plugin-manifest-sri) plugin:

```bash
npm install -D vite-plugin-manifest-sri
```

```typescript
import { defineConfig } from 'vite';
import rails from 'rails-vite-plugin';
import manifestSRI from 'vite-plugin-manifest-sri';

export default defineConfig({
  plugins: [
    rails(),
    manifestSRI(),
  ],
});
```

That's it — `integrity` and `crossorigin="anonymous"` attributes are automatically added to all script, stylesheet, and modulepreload tags when the manifest includes integrity hashes.

### Asset Discovery (Images, Fonts)

Use `import.meta.glob` in your entry point to include assets in the Vite manifest:

```js
// app/javascript/application.js
import.meta.glob(['../assets/images/**'], { eager: true });
```

Then reference them in views:

```erb
<%= vite_image_tag "app/assets/images/logo.png", alt: "Logo" %>
```

**Migrating from Propshaft?** Vite resolves asset references itself, so you don't need Propshaft's `RAILS_ASSET_URL(...)` — swap the logical path for a path relative to the referencing file, and Vite fingerprints it:

```css
/* Propshaft */
background: url(RAILS_ASSET_URL("logo.svg"));
/* Vite */
background: url(../assets/images/logo.svg);
```

- In CSS: works for any stylesheet Vite processes — an entry point, or imported from one.
- In JS: `import logoUrl from '../assets/images/logo.svg'` (or pull in a whole folder with `import.meta.glob`).
- In views: `vite_asset_path` / `vite_image_tag`, which read the Vite manifest.

## Vite Config

The install generator creates a minimal `vite.config.ts`:

```typescript
import { defineConfig } from 'vite';
import rails from 'rails-vite-plugin';

export default defineConfig({
  plugins: [
    rails(),
  ],
});
```

### Custom Vite Executable

By default, Rails tasks invoke the `vite` executable supplied by the detected
package manager. To use a compatible executable with a different name, such as
Vite+'s `vp`, configure it in Rails:

```ruby
# config/initializers/rails_vite.rb
Rails.application.config.rails_vite.vite_executable = "vp"
```

This applies to test builds, automatic builds, and `vite:build`. Start the
development server directly from `Procfile.dev`, for example with `npx vp dev`.

### Plugin Options

| Option | Default | Description |
|--------|---------|-------------|
| `input` | auto-detected | Entry point(s). If `sourceDir/entrypoints/` exists, all files in it are used. Otherwise, detects `application.{js,ts,jsx,tsx}` in `sourceDir` |
| `sourceDir` | `'app/javascript'` | Source directory. Short names are prefixed with this. Also sets the `@` import alias |
| `ssr` | — | SSR entry point |
| `ssrOutDir` | `'ssr'` | SSR output directory |
| `devMetaFile` | `'tmp/rails-vite.json'` | Dev metadata file path |
| `buildDir` | `'vite'` | Build output subdirectory inside `public/` |
| `publicDir` | `'public'` | Public directory |
| `refresh` | `true` | Paths to watch for full-page reload. `true` watches `app/views/**` and `app/helpers/**` |
| `prependSourceDirToEntries` | `true` | When `false`, entries are resolved without the `sourceDir` prefix. Set this when Vite's `root` is your `sourceDir` (see below) |

### Multiple Entry Points

```typescript
rails({
  input: ['application.js', 'admin.js'],
})
```

```erb
<!-- In application layout -->
<%= vite_tags "application.js" %>

<!-- In admin layout -->
<%= vite_tags "admin.js" %>
```

### Custom Source Directory

```typescript
rails({
  input: ['entrypoints/application.ts', 'entrypoints/admin.ts'],
  sourceDir: 'app/frontend',
})
```

```erb
<%= vite_tags "entrypoints/application.ts" %>
```

### Setting Vite's `root` to your source directory

By default, `root` is the Rails project root, so `import.meta.glob` keys and manifest entries are prefixed with `sourceDir` (e.g. `app/frontend/components/Foo.jsx`). If you prefer `vite_ruby`-style root-relative names (`components/Foo.jsx`), set Vite's `root` to your source directory and tell the plugin not to prepend `sourceDir`:

```typescript
import { fileURLToPath } from 'node:url'

export default defineConfig({
  root: fileURLToPath(new URL('./app/frontend', import.meta.url)),
  plugins: [
    rails({ sourceDir: 'app/frontend', prependSourceDirToEntries: false }),
  ],
  build: {
    outDir: fileURLToPath(new URL('./public/vite', import.meta.url)),
  },
})
```

With `root` set to the source directory, Vite emits bare manifest keys, and `prependSourceDirToEntries: false` makes the Rails helpers look them up by those bare names. Set both together. (Don't point `root` at a symlinked path — Vite resolves symlinks and emits keys that escape the root.)

## Adding Frameworks

### React

```bash
npm install -D @vitejs/plugin-react
```

```typescript
import { defineConfig } from 'vite';
import rails from 'rails-vite-plugin';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [
    react(),
    rails(),
  ],
});
```

The React Refresh preamble is injected automatically when `@vitejs/plugin-react` is detected — no manual setup needed.

### Vue

```bash
npm install -D @vitejs/plugin-vue
```

```typescript
import { defineConfig } from 'vite';
import rails from 'rails-vite-plugin';
import vue from '@vitejs/plugin-vue';

export default defineConfig({
  plugins: [
    vue(),
    rails(),
  ],
});
```

## SSR

Set `ssr` to the entry point used for server-side rendering. When you run `npx vite build --ssr`, the plugin uses this as the input and outputs to the `ssrOutDir` (default: `ssr/`).

```typescript
rails({
  ssr: 'ssr.tsx',
})
```

Build and run:

```bash
npx vite build && npx vite build --ssr
node ssr/ssr.js
```

## Auto Build

When the Vite dev server is not running, rails_vite automatically rebuilds assets on the first request if sources have changed. This is useful for system tests and quick checks without running `bin/dev`.

Freshness is determined by comparing your source files' timestamps against the build manifest's timestamp. Since the manifest lives on disk, unchanged assets are not rebuilt across process restarts — for example, on repeated local system-test runs.

Auto builds run quietly (`vite build --logLevel warn`), so they don't clutter your test output; warnings and errors are still shown. Run `rake vite:build` directly for the full build log.

Disable it:

```ruby
# config/initializers/rails_vite.rb
Rails.application.config.rails_vite.auto_build = false
```

By default, auto build is enabled in development and test (`Rails.env.local?`).

Note: for parallel test runners, disable auto build and use `rake vite:build` before the suite instead.

## Testing the Build

To verify your production build works in development:

```bash
rake vite:build         # build assets
bin/rails s             # start Rails without Vite dev server
```

Without the Vite dev server running (no `tmp/rails-vite.json`), Rails serves built assets from `public/vite/`. To switch back to dev mode, start Vite again — the dev metadata takes priority.

Clean up built assets with `rake vite:clobber`.

## Custom Paths

If you override `build.outDir` in `vite.config.ts`, tell the gem where to find things:

```ruby
# config/initializers/rails_vite.rb
Rails.application.config.rails_vite.manifest_path = Rails.root.join("public/custom/manifest.json")
Rails.application.config.rails_vite.asset_prefix = "/custom"
```

Defaults match the plugin defaults — no config needed if you follow conventions.

## Rake Tasks

| Task | Description |
|------|-------------|
| `rake vite:build` | Build assets for production |
| `rake vite:install` | Install JavaScript dependencies |
| `rake vite:clobber` | Remove `public/vite/` |

`vite:build` hooks into `assets:precompile` and `test:prepare` automatically. Skip with `SKIP_VITE_BUILD=1`.


## jsbundling Mode

If you're using [`jsbundling-rails`](https://github.com/rails/jsbundling-rails) with Propshaft and want Vite as your bundler, you don't need the `rails_vite` gem — just the npm package:

```bash
npm install -D rails-vite-plugin vite
```

```typescript
// vite.config.ts
import { defineConfig } from 'vite';
import jsbundling from 'rails-vite-plugin/jsbundling';

export default defineConfig({
  plugins: [
    jsbundling(),
  ],
});
```

**How it works:** In production, Vite builds to `public/assets/` and copies entry files to `app/assets/builds/` so Propshaft can serve them via `javascript_include_tag` and `stylesheet_link_tag`. In development, the plugin writes stub files to `app/assets/builds/` that redirect the browser to Vite's dev server for HMR.

### jsbundling Options

| Option | Default | Description |
|--------|---------|-------------|
| `input` | auto-detected | Entry point(s). If `sourceDir/entrypoints/` exists, all files in it are used. Otherwise, detects `application.{js,ts,jsx,tsx}` in `sourceDir` |
| `sourceDir` | `'app/javascript'` | Source directory. Short names are prefixed with this. Also sets the `@` import alias |
| `assetPipelineDir` | `'app/assets/builds'` | Directory where Propshaft/Sprockets picks up entry files |
| `outputDir` | `'public/assets'` | Public directory for the full Vite build output |
| `ssr` | — | SSR entry point. String or `{ entry, outDir }` |
| `refresh` | — | Paths to watch for full-page reload. `true` watches `app/views/**` and `app/helpers/**` |
| `devMetaFile` | `'tmp/rails-vite.json'` | Dev metadata file path. Set to `false` to disable |

### Replacing esbuild

In your `Procfile.dev`, replace the esbuild command:

```
web: bin/rails server -p 3000
-js: yarn build --watch
+vite: npx vite
```

CSS and JS entries in `app/javascript/entrypoints/` are auto-discovered. Both `javascript_include_tag` and `stylesheet_link_tag` work unchanged — Propshaft resolves them from `app/assets/builds/` as before.

### Frameworks

React and Vue work the same as in the standard plugin — add the framework plugin before `jsbundling()`:

```typescript
import { defineConfig } from 'vite';
import jsbundling from 'rails-vite-plugin/jsbundling';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [
    react(),
    jsbundling(),
  ],
});
```

### Upgrading to rails_vite

To switch from jsbundling mode to the full `rails_vite` gem:

1. Add `gem "rails_vite"` to your Gemfile and `bundle install`
2. Change the import in `vite.config.ts` from `rails-vite-plugin/jsbundling` to `rails-vite-plugin`
3. Replace `javascript_include_tag` / `stylesheet_link_tag` with `vite_tags` in your layouts
4. Remove `jsbundling-rails` from your Gemfile

In development, jsbundling mode writes `tmp/rails-vite.json` — the same file the `rails_vite` gem reads. You can add the gem and verify `vite_tags` works in dev before deploying.

## Migrating from vite_rails

### 1. Swap dependencies

```ruby
# Gemfile
- gem "vite_rails"
+ gem "rails_vite"
```

```json
// package.json — replace vite-plugin-ruby with rails-vite-plugin
- "vite-plugin-ruby": "^5.1.1"
+ "rails-vite-plugin": "^0.2.0"
```

### 2. Replace `vite.config.ts`

```typescript
import { defineConfig } from 'vite';
import rails from 'rails-vite-plugin';

export default defineConfig({
  plugins: [
    rails({
      sourceDir: 'app/frontend',
    }),
  ],
});
```

If you have an `entrypoints/` directory inside `sourceDir`, all files in it are auto-discovered — no need to list them. Otherwise, set `input` explicitly.

### 3. Delete files

- `config/vite.json` — settings now live in `vite.config.ts`
- `bin/vite` — no longer needed, `Procfile.dev` runs `npx vite` directly

### 4. Update layouts

Remove `vite_client_tag` and `vite_react_refresh_tag` — both are automatic now.

The `vite_javascript_tag`, `vite_stylesheet_tag`, and `vite_typescript_tag` helpers work as drop-in replacements:

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/skryukov/rails_vite.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
