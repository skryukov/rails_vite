import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import fs from 'fs'
import path from 'path'
import type { ConfigEnv, Plugin, UserConfig } from 'vite'
import jsbundling, { refreshPaths } from '../src/jsbundling'
import { bindExitHandler } from '../src/shared/cleanup'

const BUILD: ConfigEnv = { command: 'build', mode: 'production' }
const SSR_BUILD: ConfigEnv = { command: 'build', mode: 'production', isSsrBuild: true }
const SERVE: ConfigEnv = { command: 'serve', mode: 'development' }

function getConfig(plugin: Plugin, userConfig: UserConfig = {}, env: ConfigEnv = BUILD): UserConfig {
  return (plugin.config as (config: UserConfig, env: ConfigEnv) => UserConfig)(userConfig, env)
}

function callConfigResolved(plugin: Plugin, overrides: Record<string, unknown> = {}) {
  ;(plugin.configResolved as Function)({
    build: { ssr: false, outDir: 'public/assets' },
    plugins: [],
    server: { hmr: false, https: false, host: 'localhost' },
    ...overrides,
  })
}

function callWriteBundle(plugin: Plugin, bundle: Record<string, unknown>) {
  ;(plugin.writeBundle as Function)({}, bundle)
}

interface MockServer {
  httpServer: {
    once: (event: string, cb: Function) => void
    address: () => { address: string; port: number; family: string }
  }
  watcher: {
    add: ReturnType<typeof vi.fn>
    on: (event: string, cb: Function) => void
  }
  config: { logger: { info: ReturnType<typeof vi.fn> } }
  hot: { send: ReturnType<typeof vi.fn> }
  middlewares: { use: ReturnType<typeof vi.fn> }
  _emit: (event: string, ...args: unknown[]) => void
  _emitWatcher: (event: string, ...args: unknown[]) => void
}

function createMockServer(): MockServer {
  const eventListeners: Record<string, Function[]> = {}
  const watcherListeners: Record<string, Function[]> = {}

  return {
    httpServer: {
      once(event: string, cb: Function) {
        eventListeners[event] = eventListeners[event] || []
        eventListeners[event].push(cb)
      },
      address: () => ({ address: '127.0.0.1', port: 5173, family: 'IPv4' }),
    },
    watcher: {
      add: vi.fn(),
      on(event: string, cb: Function) {
        watcherListeners[event] = watcherListeners[event] || []
        watcherListeners[event].push(cb)
      },
    },
    config: { logger: { info: vi.fn() } },
    hot: { send: vi.fn() },
    middlewares: { use: vi.fn() },
    _emit(event: string, ...args: unknown[]) {
      for (const cb of eventListeners[event] || []) cb(...args)
    },
    _emitWatcher(event: string, ...args: unknown[]) {
      for (const cb of watcherListeners[event] || []) cb(...args)
    },
  }
}

vi.mock('../src/shared/cleanup.js', () => ({
  bindExitHandler: vi.fn(),
}))

vi.mock('fs', async () => {
  const actual = await vi.importActual<typeof import('fs')>('fs')
  return {
    default: {
      ...actual,
      existsSync: (filePath: string) => {
        // Mock: app/javascript/application.js exists for auto-detection
        if (filePath.endsWith('app/javascript/application.js')) return true
        // Mock: app/frontend/application.ts exists
        if (filePath.endsWith('app/frontend/application.ts')) return true
        // Mock: app/assets/entrypoints directory exists
        if (filePath.endsWith('app/assets/entrypoints')) return true
        return actual.existsSync(filePath)
      },
      readdirSync: (dir: string, options?: { withFileTypes: boolean }) => {
        if (dir.endsWith('app/assets/entrypoints') && options?.withFileTypes) {
          return [
            { name: 'application.ts', isDirectory: () => false },
            { name: 'application.css', isDirectory: () => false },
            { name: 'README.md', isDirectory: () => false },
            { name: 'admin', isDirectory: () => true },
          ]
        }
        if (dir.endsWith('app/assets/entrypoints/admin') && options?.withFileTypes) {
          return [
            { name: 'index.tsx', isDirectory: () => false },
          ]
        }
        return actual.readdirSync(dir, options as Parameters<typeof actual.readdirSync>[1])
      },
      readFileSync: (filePath: string, encoding?: string) => {
        if (typeof filePath === 'string' && filePath.includes('dev-server-index.html')) {
          return '<html><body>Vite Dev Server</body></html>'
        }
        return actual.readFileSync(filePath, encoding as BufferEncoding)
      },
      mkdirSync: vi.fn(),
      writeFileSync: vi.fn(),
      copyFileSync: vi.fn(),
      rmSync: vi.fn(),
    },
  }
})

describe('rails-vite-plugin/jsbundling', () => {
  afterEach(() => {
    delete process.env.CI
    delete process.env.RAILS_ENV
    vi.mocked(fs.mkdirSync).mockClear()
    vi.mocked(fs.writeFileSync).mockClear()
    vi.mocked(fs.copyFileSync).mockClear()
    vi.mocked(fs.rmSync).mockClear()
    vi.mocked(bindExitHandler).mockClear()
  })

  // --- Input handling ---

  it('auto-detects application.js entry point', () => {
    const plugin = jsbundling()

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/application.js')
  })

  it('auto-detects application.ts with custom sourceDir', () => {
    const plugin = jsbundling({ sourceDir: 'app/frontend' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/frontend/application.ts')
  })

  it('accepts a single input', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/application.js')
  })

  it('accepts an array of inputs', () => {
    const plugin = jsbundling({
      input: ['application.js', 'admin.js'],
    })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toEqual([
      'app/javascript/application.js',
      'app/javascript/admin.js',
    ])
  })

  it('does not prefix entries that already include sourceDir', () => {
    const plugin = jsbundling({ input: 'app/javascript/application.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/application.js')
  })

  it('does not prefix absolute paths', () => {
    const plugin = jsbundling({ input: '/absolute/path.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('/absolute/path.js')
  })

  it('accepts an object input (named entries)', () => {
    const plugin = jsbundling({
      input: { app: 'application.js', admin: 'admin/index.js' },
    })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toEqual({
      app: 'app/javascript/application.js',
      admin: 'app/javascript/admin/index.js',
    })
  })

  it('auto-discovers entrypoints directory', () => {
    const plugin = jsbundling({ sourceDir: 'app/assets' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toEqual([
      'app/assets/entrypoints/application.ts',
      'app/assets/entrypoints/application.css',
      'app/assets/entrypoints/admin/index.tsx',
    ])
  })

  it('filters non-entrypoint files from discovery', () => {
    const plugin = jsbundling({ sourceDir: 'app/assets' })

    const config = getConfig(plugin)
    const input = config!.build!.rollupOptions!.input as string[]
    expect(input).not.toContainEqual(expect.stringContaining('README.md'))
  })

  it('explicit input takes precedence over entrypoints directory', () => {
    const plugin = jsbundling({ sourceDir: 'app/assets', input: 'custom.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/assets/custom.js')
  })

  // --- Build config defaults ---

  it('builds to public/assets with /assets/ base', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.base).toBe('/assets/')
    expect(config!.build!.outDir).toBe('public/assets')
  })

  it('sets empty base for dev server', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, {}, SERVE)
    expect(config!.base).toBe('')
  })

  it('sets correct build defaults', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.build!.manifest).toBe(false)
    expect(config!.build!.assetsInlineLimit).toBe(0)
    expect(config!.publicDir).toBe(false)
  })

  it('uses unhashed entry filenames', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin)
    const output = config!.build!.rollupOptions!.output as Record<string, unknown>
    expect(output.assetFileNames).toBe('[name][extname]')
    expect(output.chunkFileNames).toBe('[name]-[hash].js')
    // entryFileNames is a function for CSS facade handling
    const entryFileNames = output.entryFileNames as Function
    expect(entryFileNames({ facadeModuleId: 'app/javascript/application.js' })).toBe('[name].js')
  })

  it('prefixes CSS facade entry filenames with _css_', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin)
    const output = config!.build!.rollupOptions!.output as Record<string, unknown>
    const entryFileNames = output.entryFileNames as Function
    expect(entryFileNames({ facadeModuleId: 'app/javascript/styles.css' })).toBe('_css_[name].js')
    expect(entryFileNames({ facadeModuleId: 'app/javascript/theme.scss' })).toBe('_css_[name].js')
    expect(entryFileNames({ facadeModuleId: null })).toBe('[name].js')
  })

  it('uses custom outputDir', () => {
    const plugin = jsbundling({
      input: 'application.js',
      outputDir: 'public/assets/builds',
    })

    const config = getConfig(plugin)
    expect(config!.build!.outDir).toBe('public/assets/builds')
    expect(config!.base).toBe('/assets/builds/')
  })

  it('derives base from custom outputDir relative to public/', () => {
    const plugin = jsbundling({
      input: 'application.js',
      outputDir: 'public/my-app',
    })

    const config = getConfig(plugin)
    expect(config!.base).toBe('/my-app/')
  })

  // --- User config passthrough ---

  it('respects user base config', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, { base: '/custom/' })
    expect(config!.base).toBe('/custom/')
  })

  it('respects user manifest config', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, { build: { manifest: 'custom-manifest.json' } })
    expect(config!.build!.manifest).toBe('custom-manifest.json')
  })

  it('respects user outDir config', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, { build: { outDir: 'custom/output' } })
    expect(config!.build!.outDir).toBe('custom/output')
  })

  it('respects user rollupOptions.input', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, { build: { rollupOptions: { input: 'custom/entry.js' } } })
    expect(config!.build!.rollupOptions!.input).toBe('custom/entry.js')
  })

  it('respects user server.cors config', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, { server: { cors: true } }, SERVE)
    expect(config!.server!.cors).toBe(true)
  })

  // --- @ alias ---

  it('provides @ alias by default', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin)
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe(
      path.resolve(process.cwd(), 'app/javascript'),
    )
  })

  it('provides @ alias with custom sourceDir', () => {
    const plugin = jsbundling({ input: 'application.ts', sourceDir: 'app/frontend' })

    const config = getConfig(plugin)
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe(
      path.resolve(process.cwd(), 'app/frontend'),
    )
  })

  it('respects existing @ alias (object form)', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, { resolve: { alias: { '@': '/custom/path' } } })
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe('/custom/path')
  })

  it('respects existing @ alias (array form)', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(
      plugin,
      { resolve: { alias: [{ find: '@', replacement: '/custom/path' }] } },
    )
    expect(config!.resolve!.alias).toEqual([
      { find: '@', replacement: '/custom/path' },
    ])
  })

  it('appends @ alias to array when not present', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(
      plugin,
      { resolve: { alias: [{ find: '~', replacement: '/other' }] } },
    )
    expect(config!.resolve!.alias).toEqual([
      { find: '~', replacement: '/other' },
      { find: '@', replacement: path.resolve(process.cwd(), 'app/javascript') },
    ])
  })

  // --- SSR builds ---

  it('returns SSR entry and outDir when ssr option is set', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: 'ssr/ssr.tsx',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.rollupOptions!.input).toBe('app/frontend/ssr/ssr.tsx')
    expect(config!.build!.outDir).toBe('public/assets-ssr')
  })

  it('uses custom SSR outDir', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: { entry: 'ssr/ssr.tsx', outDir: 'public/vite-ssr' },
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.outDir).toBe('public/vite-ssr')
  })

  it('generates SSR manifest', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: 'ssr/ssr.tsx',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.ssrManifest).toBe('ssr-manifest.json')
  })

  it('provides base and alias for SSR builds', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: 'ssr/ssr.tsx',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.base).toBe('/assets/')
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe(
      path.resolve(process.cwd(), 'app/frontend'),
    )
  })

  it('does not set client-specific config for SSR builds', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: 'ssr/ssr.tsx',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.assetsInlineLimit).toBeUndefined()
    expect(config!.build!.cssCodeSplit).toBeUndefined()
    expect(config!.publicDir).toBe(false)
  })

  it('skips build config for SSR builds without ssr option', () => {
    const plugin = jsbundling({ input: 'application.js' })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build).toBeUndefined()
    // Still provides alias
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe(
      path.resolve(process.cwd(), 'app/javascript'),
    )
  })

  it('respects user overrides for SSR builds', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: 'ssr/ssr.tsx',
    })

    const config = getConfig(plugin, {
      build: { outDir: 'custom/ssr', rollupOptions: { input: 'custom-ssr.tsx' } },
    }, SSR_BUILD)
    expect(config!.build!.outDir).toBe('custom/ssr')
    expect(config!.build!.rollupOptions!.input).toBe('custom-ssr.tsx')
  })

  it('adds noExternal for SSR builds', () => {
    const plugin = jsbundling({
      sourceDir: 'app/frontend',
      ssr: 'ssr/ssr.tsx',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.ssr!.noExternal).toEqual(['rails-vite-plugin'])
  })

  // --- Environment guards ---

  it('throws in CI environment during serve', () => {
    process.env.CI = 'true'
    const plugin = jsbundling({ input: 'application.js' })

    expect(() => getConfig(plugin, {}, SERVE)).toThrowError(
      'should not run the Vite dev server in CI',
    )
  })

  it('throws in production environment during serve', () => {
    process.env.RAILS_ENV = 'production'
    const plugin = jsbundling({ input: 'application.js' })

    expect(() => getConfig(plugin, {}, SERVE)).toThrowError(
      'should not run the Vite dev server in production',
    )
  })

  it('allows build in CI', () => {
    process.env.CI = 'true'
    const plugin = jsbundling({ input: 'application.js' })

    expect(() => getConfig(plugin)).not.toThrow()
  })

  it('allows build in production', () => {
    process.env.RAILS_ENV = 'production'
    const plugin = jsbundling({ input: 'application.js' })

    expect(() => getConfig(plugin)).not.toThrow()
  })

  // --- Refresh paths ---

  it('exports refreshPaths', () => {
    expect(refreshPaths).toEqual([
      'app/views/**/*.{erb,slim,haml}',
      'app/helpers/**/*.rb',
    ])
  })

  it('has the correct plugin name', () => {
    const plugin = jsbundling({ input: 'application.js' })
    expect(plugin.name).toBe('rails-vite-jsbundling')
  })

  it('enforces post', () => {
    const plugin = jsbundling({ input: 'application.js' })
    expect(plugin.enforce).toBe('post')
  })

  // --- Placeholder stubs ---

  it('writes placeholder stubs during serve', () => {
    const plugin = jsbundling({ input: 'application.js' })

    // Clear mocks right before to isolate calls from plugin construction
    vi.mocked(fs.mkdirSync).mockClear()
    vi.mocked(fs.writeFileSync).mockClear()

    getConfig(plugin, {}, SERVE)

    // writePlaceholderStubs creates the directory and writes JS + CSS stubs
    const mkdirCalls = vi.mocked(fs.mkdirSync).mock.calls
    expect(mkdirCalls.some(([dir]) => dir === 'app/assets/builds')).toBe(true)

    const writeCalls = vi.mocked(fs.writeFileSync).mock.calls
    const jsStub = writeCalls.find(([path]) => path === 'app/assets/builds/application.js')
    const cssStub = writeCalls.find(([path]) => path === 'app/assets/builds/application.css')
    expect(jsStub).toBeDefined()
    expect(String(jsStub![1])).toContain('placeholder')
    expect(cssStub).toBeDefined()
    expect(String(cssStub![1])).toContain('placeholder')
  })

  it('does not write placeholder stubs during build', () => {
    const plugin = jsbundling({ input: 'application.js' })

    getConfig(plugin, {}, BUILD)

    expect(fs.writeFileSync).not.toHaveBeenCalled()
  })

  // --- writeBundle ---

  it('copies entry JS and extracted CSS to assetPipelineDir', () => {
    const plugin = jsbundling({ input: 'application.js' })
    getConfig(plugin)
    callConfigResolved(plugin)

    const bundle = {
      'application.js': { type: 'chunk', isEntry: true },
      'application.css': { type: 'asset' },
    }
    callWriteBundle(plugin, bundle)

    const copiedDests = vi.mocked(fs.copyFileSync).mock.calls.map(([, dest]) => dest)
    expect(copiedDests).toContain(path.join('app/assets/builds', 'application.js'))
    expect(copiedDests).toContain(path.join('app/assets/builds', 'application.css'))
  })

  it('does not copy shared chunk CSS to assetPipelineDir', () => {
    const plugin = jsbundling({ input: 'application.js' })
    getConfig(plugin)
    callConfigResolved(plugin)

    const bundle = {
      'application.js': { type: 'chunk', isEntry: true },
      'application.css': { type: 'asset' },
      'vendor-abc123.css': { type: 'asset' },
    }
    callWriteBundle(plugin, bundle)

    const copiedDests = vi.mocked(fs.copyFileSync).mock.calls.map(([, dest]) => dest)
    expect(copiedDests).toContain(path.join('app/assets/builds', 'application.js'))
    expect(copiedDests).toContain(path.join('app/assets/builds', 'application.css'))
    expect(copiedDests).not.toContainEqual(expect.stringContaining('vendor'))
  })

  it('does not copy non-entry chunks to assetPipelineDir', () => {
    const plugin = jsbundling({ input: 'application.js' })
    getConfig(plugin)
    callConfigResolved(plugin)

    const bundle = {
      'application.js': { type: 'chunk', isEntry: true },
      'shared-chunk-abc.js': { type: 'chunk', isEntry: false },
    }
    callWriteBundle(plugin, bundle)

    const copiedDests = vi.mocked(fs.copyFileSync).mock.calls.map(([, dest]) => dest)
    expect(copiedDests).toHaveLength(1)
    expect(copiedDests[0]).toContain('application.js')
  })

  it('removes CSS facade JS chunks from bundle', () => {
    const plugin = jsbundling({
      input: { app: 'application.js', styles: 'application.css' },
    })
    getConfig(plugin)
    callConfigResolved(plugin)

    const bundle: Record<string, unknown> = {
      'app.js': { type: 'chunk', isEntry: true },
      '_css_styles.js': { type: 'chunk', isEntry: true },
      'styles.css': { type: 'asset' },
    }
    ;(plugin.generateBundle as Function)({}, bundle)

    expect(bundle).not.toHaveProperty('_css_styles.js')
    expect(bundle).toHaveProperty('app.js')
    expect(bundle).toHaveProperty('styles.css')
  })

  it('skips writeBundle for SSR builds', () => {
    const plugin = jsbundling({ input: 'application.js', ssr: 'ssr.tsx' })
    getConfig(plugin, {}, SSR_BUILD)
    callConfigResolved(plugin, { build: { ssr: true, outDir: 'public/assets-ssr' } })

    callWriteBundle(plugin, { 'ssr.js': { type: 'chunk', isEntry: true } })

    expect(fs.copyFileSync).not.toHaveBeenCalled()
  })

  // --- configureServer: entrypoint watcher ---

  it('does not match files in sibling directories with similar prefix', () => {
    vi.useFakeTimers()

    const plugin = jsbundling({ sourceDir: 'app/assets' })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    const server = createMockServer()
    ;(plugin.configureServer as Function)(server)
    server._emit('listening')

    vi.mocked(fs.writeFileSync).mockClear()
    vi.mocked(fs.rmSync).mockClear()

    // File in a sibling directory that shares the entrypoints prefix
    const epAbsDir = path.resolve('app/assets', 'entrypoints')
    const siblingFile = `${epAbsDir}-v2/something.js`

    server._emitWatcher('add', siblingFile)
    vi.advanceTimersByTime(200)

    // No stubs should have been regenerated for a sibling dir file
    expect(fs.rmSync).not.toHaveBeenCalled()

    vi.useRealTimers()
  })

  it('matches files inside the entrypoints directory', () => {
    vi.useFakeTimers()

    const plugin = jsbundling({ sourceDir: 'app/assets' })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    const server = createMockServer()
    ;(plugin.configureServer as Function)(server)
    server._emit('listening')

    vi.mocked(fs.writeFileSync).mockClear()
    vi.mocked(fs.rmSync).mockClear()

    const epAbsDir = path.resolve('app/assets', 'entrypoints')
    const entrypointFile = `${epAbsDir}/new-entry.js`

    server._emitWatcher('add', entrypointFile)
    vi.advanceTimersByTime(200)

    // Stubs should have been regenerated (rmSync for old stubs + writeFileSync for new)
    expect(server.config.logger.info).toHaveBeenCalledWith(
      expect.stringContaining('new entrypoint'),
    )

    vi.useRealTimers()
  })

  // --- configureServer: dev middleware ---

  it('sets Content-Type header on dev server index page', () => {
    const plugin = jsbundling({ input: 'application.js' })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    const server = createMockServer()
    const setupMiddleware = (plugin.configureServer as Function)(server)
    setupMiddleware()

    const middleware = vi.mocked(server.middlewares.use).mock.calls[0][0] as Function
    const res = {
      statusCode: 0,
      setHeader: vi.fn(),
      end: vi.fn(),
    }

    middleware({ url: '/index.html' }, res, vi.fn())

    expect(res.statusCode).toBe(404)
    expect(res.setHeader).toHaveBeenCalledWith('Content-Type', 'text/html')
    expect(res.end).toHaveBeenCalled()
  })

  // --- configureServer: devMetaFile ---

  it('creates parent directory for devMetaFile', () => {
    const plugin = jsbundling({
      input: 'application.js',
      devMetaFile: 'some/nested/dir/meta.json',
    })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    vi.mocked(fs.mkdirSync).mockClear()

    const server = createMockServer()
    ;(plugin.configureServer as Function)(server)
    server._emit('listening')

    const mkdirCalls = vi.mocked(fs.mkdirSync).mock.calls
    expect(mkdirCalls).toContainEqual([
      path.dirname('some/nested/dir/meta.json'),
      { recursive: true },
    ])
  })

  // --- writeDevStubs: CSS entries ---

  it('writes empty CSS stubs for CSS entries', () => {
    const plugin = jsbundling({ sourceDir: 'app/assets' })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    const server = createMockServer()
    ;(plugin.configureServer as Function)(server)
    server._emit('listening')

    const writeCalls = vi.mocked(fs.writeFileSync).mock.calls
    // Find the dev CSS stub (not placeholder — dev stubs are written after listening)
    const cssStubs = writeCalls.filter(([p, content]) =>
      String(p).endsWith('application.css') && String(content).includes('dev stub')
    )
    expect(cssStubs).toHaveLength(1)
    // CSS stubs are empty — actual CSS is injected by @vite/client through JS imports
    expect(String(cssStubs[0][1])).not.toContain('@import')
  })

  it('imports CSS entries in JS stubs for HMR', () => {
    const plugin = jsbundling({ sourceDir: 'app/assets' })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    const server = createMockServer()
    ;(plugin.configureServer as Function)(server)
    server._emit('listening')

    const writeCalls = vi.mocked(fs.writeFileSync).mock.calls
    // Find the JS dev stub for application (not placeholder)
    const jsStub = writeCalls.find(([p, content]) =>
      String(p).endsWith('application.js') && String(content).includes('@vite/client')
    )
    expect(jsStub).toBeDefined()
    // JS stub should import the CSS entry for HMR
    expect(String(jsStub![1])).toContain('entrypoints/application.css')
  })

  // --- writeDevStubs: no duplicate tracking ---

  it('does not track duplicate paths in writtenStubs', () => {
    // Each stub path should appear only once in writtenStubs.
    // We test this via the exit handler: it should not delete the same file twice.
    const plugin = jsbundling({ sourceDir: 'app/assets' })
    getConfig(plugin, {}, SERVE)
    callConfigResolved(plugin)

    const server = createMockServer()
    ;(plugin.configureServer as Function)(server)
    server._emit('listening')

    // Grab the exit handler function
    const exitHandler = vi.mocked(bindExitHandler).mock.calls[0][0]

    vi.mocked(fs.rmSync).mockClear()
    exitHandler()

    // Check no duplicate paths in rmSync calls
    const removedPaths = vi.mocked(fs.rmSync).mock.calls.map(([p]) => p)
    const uniquePaths = [...new Set(removedPaths)]
    expect(removedPaths).toEqual(uniquePaths)
  })
})
