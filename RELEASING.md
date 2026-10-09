# Releasing

1. Bump `lib/rails_vite/version.rb` and/or `packages/rails-vite-plugin/package.json`.
2. Rename `## Unreleased` in `CHANGELOG.md` to `## rails_vite@X / rails-vite-plugin@Y - YYYY-MM-DD` (list only the packages you release, gem first).
3. Merge to `main`, then push a tag per package:

   ```sh
   git tag rails_vite@X && git tag rails-vite-plugin@Y
   git push origin rails_vite@X rails-vite-plugin@Y
   ```

4. Approve the `release` environment in Actions, once per tag.

The Release workflow checks that the tag matches the version, publishes with trusted publishing, and creates the GitHub release from the CHANGELOG section.

Prereleases use `0.3.0.rc1` for the gem and `0.3.0-rc.1` for npm. npm prereleases go to the `next` dist-tag, and the GitHub release is marked as a prerelease.

## One-time setup

- GitHub: Settings → Environments → `release`: add yourself as a required reviewer and allow only tags matching `rails_vite@*` and `rails-vite-plugin@*`.
- npmjs.com: `rails-vite-plugin` → Settings → Trusted Publisher → GitHub Actions: `skryukov` / `rails_vite`, workflow `release.yml`, environment `release`. Then set publishing access to require 2FA and disallow tokens.
- rubygems.org: `rails_vite` → Trusted publishers → GitHub Actions: `skryukov` / `rails_vite`, workflow `release.yml`, environment `release`.
