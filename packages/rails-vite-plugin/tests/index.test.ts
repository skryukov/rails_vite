import { afterEach, describe, expect, it, vi } from 'vitest'
import fs from 'fs'
import path from 'path'
import type { ConfigEnv, Plugin, UserConfig } from 'vite'
import rails, { refreshPaths } from '../src'

const BUILD: ConfigEnv = { command: 'build', mode: 'production' }
const SSR_BUILD: ConfigEnv = { command: 'build', mode: 'production', isSsrBuild: true }
const SERVE: ConfigEnv = { command: 'serve', mode: 'development' }

function getConfig(plugin: Plugin, userConfig: UserConfig = {}, env: ConfigEnv = BUILD): UserConfig {
  return (plugin.config as (config: UserConfig, env: ConfigEnv) => UserConfig)(userConfig, env)
}

vi.mock('fs', async () => {
  const actual = await vi.importActual<typeof import('fs')>('fs')
  return {
    default: {
      ...actual,
      existsSync: (filePath: string) => {
        if (filePath.endsWith('app/javascript/application.js')) return true
        if (filePath.endsWith('app/frontend/application.ts')) return true
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
    },
  }
})

describe('rails-vite-plugin', () => {
  afterEach(() => {
    delete process.env.CI
    delete process.env.RAILS_ENV
  })

  // --- Input handling ---

  it('auto-detects application.js entry point', () => {
    const plugin = rails()

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/application.js')
  })

  it('auto-detects application.ts with custom sourceDir', () => {
    const plugin = rails({ sourceDir: 'app/frontend' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/frontend/application.ts')
  })

  it('accepts a single input', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/application.js')
  })

  it('accepts an array of inputs', () => {
    const plugin = rails({
      input: ['application.js', 'admin.js'],
    })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toEqual([
      'app/javascript/application.js',
      'app/javascript/admin.js',
    ])
  })

  it('does not prefix entries that already include sourceDir', () => {
    const plugin = rails({ input: 'app/javascript/application.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/application.js')
  })

  it('does not prefix absolute paths', () => {
    const plugin = rails({ input: '/absolute/path.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('/absolute/path.js')
  })

  it('accepts an object input (named entries)', () => {
    const plugin = rails({
      input: { app: 'application.js', admin: 'admin/index.js' },
    })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toEqual({
      app: 'app/javascript/application.js',
      admin: 'app/javascript/admin/index.js',
    })
  })

  it('auto-discovers entrypoints directory', () => {
    const plugin = rails({ sourceDir: 'app/assets' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toEqual([
      'app/assets/entrypoints/application.ts',
      'app/assets/entrypoints/application.css',
      'app/assets/entrypoints/admin/index.tsx',
    ])
  })

  it('filters non-entrypoint files from discovery', () => {
    const plugin = rails({ sourceDir: 'app/assets' })

    const config = getConfig(plugin)
    const input = config!.build!.rollupOptions!.input as string[]
    expect(input).not.toContainEqual(expect.stringContaining('README.md'))
  })

  it('explicit input takes precedence over entrypoints directory', () => {
    const plugin = rails({ sourceDir: 'app/assets', input: 'custom.js' })

    const config = getConfig(plugin)
    expect(config!.build!.rollupOptions!.input).toBe('app/assets/custom.js')
  })

  // --- Build config defaults ---

  it('sets correct base for build', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.base).toBe('/vite/')
  })

  it('sets empty base for dev server', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, {}, SERVE)
    expect(config!.base).toBe('')
  })

  it('sets correct build defaults', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.build!.manifest).toBe('manifest.json')
    expect(config!.build!.outDir).toBe(path.join('public', 'vite'))
    expect(config!.build!.assetsInlineLimit).toBe(0)
    expect(config!.publicDir).toBe(false)
  })

  it('uses custom buildDir', () => {
    const plugin = rails({
      input: 'application.js',
      buildDir: 'assets',
    })

    const config = getConfig(plugin)
    expect(config!.base).toBe('/assets/')
    expect(config!.build!.outDir).toBe(path.join('public', 'assets'))
  })

  it('uses custom publicDir', () => {
    const plugin = rails({
      input: 'application.js',
      publicDir: 'dist',
    })

    const config = getConfig(plugin)
    expect(config!.build!.outDir).toBe(path.join('dist', 'vite'))
  })

  // --- User config passthrough ---

  it('respects user base config', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { base: '/custom/' })
    expect(config!.base).toBe('/custom/')
  })

  it('respects user manifest config', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { build: { manifest: 'custom-manifest.json' } })
    expect(config!.build!.manifest).toBe('custom-manifest.json')
  })

  it('respects user outDir config', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { build: { outDir: 'custom/output' } })
    expect(config!.build!.outDir).toBe('custom/output')
  })

  it('respects user rollupOptions.input', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { build: { rollupOptions: { input: 'custom/entry.js' } } })
    expect(config!.build!.rollupOptions!.input).toBe('custom/entry.js')
  })

  it('respects user server.cors config', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { server: { cors: true } }, SERVE)
    expect(config!.server!.cors).toBe(true)
  })

  // --- @ alias ---

  it('provides @ alias by default', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin)
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe(
      path.resolve(process.cwd(), 'app/javascript'),
    )
  })

  it('provides @ alias with custom sourceDir', () => {
    const plugin = rails({ input: 'application.ts', sourceDir: 'app/frontend' })

    const config = getConfig(plugin)
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe(
      path.resolve(process.cwd(), 'app/frontend'),
    )
  })

  it('respects existing @ alias (object form)', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { resolve: { alias: { '@': '/custom/path' } } })
    expect((config!.resolve!.alias as Record<string, string>)['@']).toBe('/custom/path')
  })

  it('respects existing @ alias (array form)', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(
      plugin,
      { resolve: { alias: [{ find: '@', replacement: '/custom/path' }] } },
    )
    expect(config!.resolve!.alias).toEqual([
      { find: '@', replacement: '/custom/path' },
    ])
  })

  it('appends @ alias to array when not present', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(
      plugin,
      { resolve: { alias: [{ find: '~', replacement: '/other' }] } },
    )
    expect(config!.resolve!.alias).toEqual([
      { find: '~', replacement: '/other' },
      { find: '@', replacement: path.resolve(process.cwd(), 'app/javascript') },
    ])
  })

  // --- SSR ---

  it('configures SSR build via isSsrBuild', () => {
    const plugin = rails({
      input: 'application.js',
      ssr: 'ssr.js',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.manifest).toBe(false)
    expect(config!.build!.ssrManifest).toBe('ssr-manifest.json')
    expect(config!.build!.outDir).toBe('ssr')
    expect(config!.build!.rollupOptions!.input).toBe('app/javascript/ssr.js')
  })

  it('uses custom SSR output directory', () => {
    const plugin = rails({
      input: 'application.js',
      ssr: 'ssr.js',
      ssrOutDir: 'custom-ssr',
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.outDir).toBe('custom-ssr')
  })

  it('accepts SSR as an array', () => {
    const plugin = rails({
      input: 'application.js',
      ssr: ['ssr.js', 'ssr-worker.js'],
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.rollupOptions!.input).toEqual([
      'app/javascript/ssr.js',
      'app/javascript/ssr-worker.js',
    ])
  })

  it('accepts SSR as an object', () => {
    const plugin = rails({
      input: 'application.js',
      ssr: { main: 'ssr.js' },
    })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.rollupOptions!.input).toEqual({
      main: 'app/javascript/ssr.js',
    })
  })

  it('uses default input for SSR when no ssr option provided', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, {}, SSR_BUILD)
    expect(config!.build!.rollupOptions!.input).toBeUndefined()
  })

  it('prevents plugin from being externalized in SSR', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin)
    expect(config!.ssr!.noExternal).toEqual(['rails-vite-plugin'])
  })

  it('respects user noExternal: true', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { ssr: { noExternal: true } })
    expect(config!.ssr!.noExternal).toBe(true)
  })

  it('merges user noExternal array', () => {
    const plugin = rails({ input: 'application.js' })

    const config = getConfig(plugin, { ssr: { noExternal: ['foo'] } })
    expect(config!.ssr!.noExternal).toEqual(['foo', 'rails-vite-plugin'])
  })

  // --- Environment guards ---

  it('throws in CI environment during serve', () => {
    process.env.CI = 'true'
    const plugin = rails({ input: 'application.js' })

    expect(() => getConfig(plugin, {}, SERVE)).toThrowError(
      'should not run the Vite dev server in CI',
    )
  })

  it('throws in production environment during serve', () => {
    process.env.RAILS_ENV = 'production'
    const plugin = rails({ input: 'application.js' })

    expect(() => getConfig(plugin, {}, SERVE)).toThrowError(
      'should not run the Vite dev server in production',
    )
  })

  it('allows build in CI', () => {
    process.env.CI = 'true'
    const plugin = rails({ input: 'application.js' })

    expect(() => getConfig(plugin)).not.toThrow()
  })

  it('allows build in production', () => {
    process.env.RAILS_ENV = 'production'
    const plugin = rails({ input: 'application.js' })

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
    const plugin = rails({ input: 'application.js' })
    expect(plugin.name).toBe('rails-vite')
  })

  it('enforces post', () => {
    const plugin = rails({ input: 'application.js' })
    expect(plugin.enforce).toBe('post')
  })
})
