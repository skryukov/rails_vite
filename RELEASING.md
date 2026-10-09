# Releasing

1. Bump `lib/rails_vite/version.rb` and/or `packages/rails-vite-plugin/package.json`.
2. Rename `## Unreleased` in `CHANGELOG.md` to `## rails_vite@X / rails-vite-plugin@Y - YYYY-MM-DD` (list only the packages you release, gem first).
3. Merge to `main`, then push a tag per package. Each tag publishes right away:

   ```sh
   git tag rails_vite@X && git tag rails-vite-plugin@Y
   git push origin rails_vite@X rails-vite-plugin@Y
   ```

The Release workflow checks that the tag matches the version, publishes with trusted publishing, and creates the GitHub release from the CHANGELOG section.

Prereleases use `0.3.0.rc1` for the gem and `0.3.0-rc.1` for npm. npm prereleases go to the `next` dist-tag, and the GitHub release is marked as a prerelease.

For the final release after a release candidate, rename the RC heading to the final versions rather than adding a new one, so the notes keep every change.

Push tags one by one or by name, never with `git push --tags`: GitHub skips workflows when more than three tags are pushed at once.

## One-time setup

- npmjs.com: `rails-vite-plugin` → Settings → Trusted Publisher → GitHub Actions: `skryukov` / `rails_vite`, workflow `release.yml`, no environment. Then set publishing access to require 2FA and disallow tokens.
- rubygems.org: `rails_vite` → Trusted publishers → GitHub Actions: `skryukov` / `rails_vite`, workflow `release.yml`, no environment.
