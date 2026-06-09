import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { build } from 'vite'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import rails from '../src'

// Real `vite build` (no mocked fs) — the regression guard for issue #22.
// Mocked hook tests can't see the actual manifest keys Vite emits, which is
// exactly how the prefix mismatch went unnoticed. This builds for real and
// asserts the on-disk manifest + rails-vite.json.
describe('root == sourceDir, real build', () => {
  let dir: string

  beforeAll(() => {
    // realpath so root/input share one symlink space (macOS /var -> /private/var);
    // an absolute input avoids depending on the process cwd.
    dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'rv-issue22-')))
    fs.mkdirSync(path.join(dir, 'app/frontend/entrypoints'), { recursive: true })
    fs.writeFileSync(path.join(dir, 'app/frontend/entrypoints/demos.js'), 'export const demo = 1\n')
  })

  afterAll(() => {
    fs.rmSync(dir, { recursive: true, force: true })
  })

  function readManifest(outDir: string): Record<string, unknown> {
    for (const p of [path.join(outDir, '.vite', 'manifest.json'), path.join(outDir, 'manifest.json')]) {
      if (fs.existsSync(p)) return JSON.parse(fs.readFileSync(p, 'utf8'))
    }
    throw new Error(`manifest not found under ${outDir}`)
  }

  it('emits bare manifest keys and empty sourceDir when prependSourceDirToEntries is false', async () => {
    const root = path.join(dir, 'app/frontend')
    const outDir = path.join(dir, 'out')

    await build({
      root,
      configFile: false,
      logLevel: 'error',
      plugins: [
        rails({
          sourceDir: root,
          input: path.join(root, 'entrypoints/demos.js'),
          prependSourceDirToEntries: false,
        }),
      ],
      build: { outDir, emptyOutDir: true },
    })

    const manifest = readManifest(outDir)
    const meta = JSON.parse(fs.readFileSync(path.join(outDir, 'rails-vite.json'), 'utf8'))

    // Vite keys the entry relative to root -> bare, no sourceDir prefix.
    expect(Object.keys(manifest)).toContain('entrypoints/demos.js')
    // The gem must therefore NOT prepend sourceDir.
    expect(meta.sourceDir).toBe('')
  })
})
