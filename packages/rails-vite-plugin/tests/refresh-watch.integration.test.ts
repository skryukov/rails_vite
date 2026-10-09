import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { createServer, type InlineConfig, type ViteDevServer } from 'vite'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import rails from '../src'

// Real dev server and chokidar watcher. Vite disables globbing in chokidar, so
// refresh globs passed to `watcher.add` as-is are literal, missing paths.
describe('refresh paths, real watcher', () => {
  const originalCwd = process.cwd()
  const originalCI = process.env.CI
  let dir: string
  let server: ViteDevServer | undefined

  beforeEach(() => {
    dir = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'rv-refresh-')))
    for (const file of ['app/views/users/partials/_user.html.erb', 'app/views/admin/index.html.erb', 'app/javascript/application.js']) {
      fs.mkdirSync(path.dirname(path.join(dir, file)), { recursive: true })
      fs.writeFileSync(path.join(dir, file), '')
    }
    // Refresh globs are relative to the Rails root, which is the cwd.
    process.chdir(dir)
    delete process.env.CI
  })

  afterEach(async () => {
    await server?.close()
    server = undefined
    process.chdir(originalCwd)
    if (originalCI !== undefined) process.env.CI = originalCI
    fs.rmSync(dir, { recursive: true, force: true })
  })

  async function startServer(config: InlineConfig = {}) {
    server = await createServer({
      root: dir,
      configFile: false,
      logLevel: 'silent',
      plugins: [rails({ input: 'app/javascript/application.js' })],
      ...config,
      server: {
        middlewareMode: true,
        ws: false,
        ...config.server,
        // Use non-recursive fs.watch, like inotify on Linux, instead of macOS FSEvents.
        watch: { useFsEvents: false, ...config.server?.watch },
      },
    })
    return { server, send: vi.spyOn(server.hot, 'send') }
  }

  function watchedDirs(server: ViteDevServer) {
    return Object.keys(server.watcher.getWatched()).map((watched) => path.relative(dir, watched))
  }

  async function expectReloadAfterEditing(send: ReturnType<typeof vi.spyOn>, file: string) {
    fs.appendFileSync(path.join(dir, file), 'edit')
    await vi.waitFor(() => expect(send).toHaveBeenCalledWith({ type: 'full-reload', path: '*' }), { timeout: 3000 })
  }

  it('watches nested view directories and reloads on template changes', async () => {
    const { server, send } = await startServer()

    await vi.waitFor(() => expect(watchedDirs(server)).toContain('app/views/users/partials'), { timeout: 3000 })
    await expectReloadAfterEditing(send, 'app/views/users/partials/_user.html.erb')
  })

  it('watches views outside of the Vite root', async () => {
    const { server, send } = await startServer({ root: path.join(dir, 'app/javascript') })

    await vi.waitFor(() => expect(watchedDirs(server)).toContain('app/views/users/partials'), { timeout: 3000 })
    await expectReloadAfterEditing(send, 'app/views/users/partials/_user.html.erb')
  })

  it('respects server.watch.ignored', async () => {
    const { server, send } = await startServer({ server: { watch: { ignored: ['**/app/views/admin/**'] } } })

    await vi.waitFor(() => expect(watchedDirs(server)).toContain('app/views/users/partials'), { timeout: 3000 })
    expect(watchedDirs(server)).not.toContain('app/views/admin')

    fs.appendFileSync(path.join(dir, 'app/views/admin/index.html.erb'), 'edit')
    await expectReloadAfterEditing(send, 'app/views/users/partials/_user.html.erb')
    await new Promise((resolve) => setTimeout(resolve, 200))
    expect(send).toHaveBeenCalledTimes(1)
  })
})
