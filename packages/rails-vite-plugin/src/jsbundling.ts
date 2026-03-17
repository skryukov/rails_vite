import fs from 'fs'
import path from 'path'
import picomatch from 'picomatch'
import {
  Plugin,
  UserConfig,
  ConfigEnv,
  ResolvedConfig,
  loadEnv,
  defaultAllowedOrigins,
} from 'vite'

import type { InputOption, ResolvedEntry } from './shared/types.js'
import { ORIGIN_PLACEHOLDER } from './shared/types.js'
import { resolveEntries, entriesToRollupInput, prefixWithSourceDir, detectEntrypointsDir, discoverEntrypointInputs, detectEntrypoint, isEntrypointFile } from './shared/entries.js'
import { resolveAlias } from './shared/alias.js'
import { resolveDevServerUrl, isAddressInfo, replaceOriginPlaceholder } from './shared/dev-server.js'
import { resolveBundlerOptionsKey, getUserBundlerInput } from './shared/bundler-compat.js'
import { ensureCommandShouldRunInEnvironment } from './shared/env-guard.js'
import { refreshPaths, resolveRefreshPaths } from './shared/refresh.js'
import { cssExtensions } from './shared/css.js'
import { readDevServerIndexHtml } from './shared/dev-server-page.js'
import { resolveNoExternal } from './shared/ssr.js'
import { bindExitHandler } from './shared/cleanup.js'

export type { InputOption }
export { refreshPaths }

const CSS_FACADE_PREFIX = '_css_'

export interface JsbundlingOptions {
  input?: InputOption
  sourceDir?: string
  /** Directory where Propshaft/Sprockets picks up entry files for Rails helpers.
   *  Default: 'app/assets/builds' */
  assetPipelineDir?: string
  /** Public directory for the full Vite build output (chunks, assets).
   *  Default: 'public/assets' */
  outputDir?: string
  /** SSR entry point for Inertia server-side rendering.
   *  String is a path relative to sourceDir (e.g., 'ssr/ssr.tsx').
   *  Object form allows customizing the output directory. */
  ssr?: string | { entry: string; outDir?: string }
  refresh?: boolean | string | string[]
  /** Path to write dev server metadata JSON (default: 'tmp/rails-vite.json').
   *  Set to false to disable. Useful as a bridge for progressive upgrade to the rails_vite gem. */
  devMetaFile?: string | false
}

export default function jsbundling(options: JsbundlingOptions = {}): Plugin {
  const sourceDir = options.sourceDir ?? 'app/javascript'
  const epDir = detectEntrypointsDir(sourceDir)
  const input = options.input ?? (epDir ? discoverEntrypointInputs(sourceDir, epDir) : detectEntrypoint(sourceDir))
  const assetPipelineDir = options.assetPipelineDir ?? 'app/assets/builds'
  const outputDir = options.outputDir ?? 'public/assets'
  // The URL prefix matching outputDir under public/ — used as Vite's `base` in production
  // so that dynamic import() URLs resolve to the right place.
  const buildBase = '/' + path.relative('public', outputDir) + '/'
  const devMetaPath = options.devMetaFile !== false
    ? (options.devMetaFile ?? path.join('tmp', 'rails-vite.json'))
    : null

  const entries = resolveEntries(input, sourceDir)
  const rollupInput = entriesToRollupInput(entries, typeof options.input === 'object' && !Array.isArray(options.input))
  const ssrConfig = resolveSsrConfig(options.ssr, sourceDir, outputDir)

  let resolvedConfig: ResolvedConfig
  let reactRefresh = false
  let devServerUrl: string | null = null

  // Track stubs written in dev so we can clean them up
  const writtenStubs: string[] = []

  return {
    name: 'rails-vite-jsbundling',
    enforce: 'post',

    config(userConfig: UserConfig, { command, mode, isSsrBuild }: ConfigEnv): UserConfig {
      const env = loadEnv(mode, userConfig.envDir || process.cwd(), '')

      ensureCommandShouldRunInEnvironment(command, env, 'rails-vite-plugin/jsbundling')

      // @ts-expect-error -- `this.meta.rolldownVersion` exists in Vite 8+
      const bundlerOptionsKey = resolveBundlerOptionsKey(this.meta)
      const userBundlerInput = getUserBundlerInput(userConfig)

      // SSR builds get minimal config — just entry, outDir, base, and alias.
      // No asset pipeline stubs or client-specific settings.
      if (isSsrBuild) {
        return {
          base: userConfig.base ?? (command === 'build' ? buildBase : ''),
          publicDir: userConfig.publicDir ?? false,
          ...(ssrConfig ? {
            build: {
              ssrManifest: userConfig.build?.ssrManifest ?? 'ssr-manifest.json',
              outDir: userConfig.build?.outDir ?? ssrConfig.outDir,
              [bundlerOptionsKey]: {
                input: userBundlerInput ?? ssrConfig.entry,
              },
            },
          } : {}),
          resolve: {
            alias: resolveAlias(userConfig.resolve?.alias, sourceDir),
          },
          ssr: {
            noExternal: resolveNoExternal(userConfig),
          },
        }
      }

      return {
        base: userConfig.base ?? (command === 'build' ? buildBase : ''),
        publicDir: userConfig.publicDir ?? false,
        build: {
          manifest: userConfig.build?.manifest ?? false,
          outDir: userConfig.build?.outDir ?? outputDir,
          [bundlerOptionsKey]: {
            input: userBundlerInput ?? rollupInput,
            output: {
              entryFileNames: (chunkInfo: { facadeModuleId?: string | null }) => {
                if (chunkInfo.facadeModuleId && cssExtensions.test(chunkInfo.facadeModuleId)) {
                  return `${CSS_FACADE_PREFIX}[name].js`
                }
                return '_[name]-[hash].js'
              },
              chunkFileNames: '[name]-[hash].js',
              assetFileNames: '[name][extname]',
            },
          },
          assetsInlineLimit: userConfig.build?.assetsInlineLimit ?? 0,
          cssCodeSplit: true,
        },
        server: {
          origin: command === 'serve' ? (userConfig.server?.origin ?? ORIGIN_PLACEHOLDER) : undefined,
          cors: userConfig.server?.cors ?? {
            origin: userConfig.server?.origin ?? defaultAllowedOrigins,
          },
        },
        resolve: {
          alias: resolveAlias(userConfig.resolve?.alias, sourceDir),
        },
        ssr: {
          noExternal: resolveNoExternal(userConfig),
        },
      }
    },

    configResolved(config) {
      resolvedConfig = config
      reactRefresh = config.plugins.some((p) => p.name === 'vite:react-babel' || p.name === 'vite:react-swc')
    },

    generateBundle(_, bundle) {
      // Rollup wraps CSS entries in empty JS facade chunks. Delete them —
      // the real CSS is emitted as an asset by Vite's CSS pipeline.
      for (const fileName of Object.keys(bundle)) {
        if (fileName.startsWith(CSS_FACADE_PREFIX)) {
          delete bundle[fileName]
        }
      }
    },

    writeBundle(_, bundle) {
      // SSR bundles are Node.js server code — not served to browsers.
      if (resolvedConfig.build.ssr) return

      fs.mkdirSync(assetPipelineDir, { recursive: true })

      const outDir = resolvedConfig.build.outDir
      const entryNames = new Set(entries.map(e => e.name))

      for (const [fileName, chunk] of Object.entries(bundle)) {
        const isEntryJs = chunk.type === 'chunk' && chunk.isEntry
        const isEntryCss = chunk.type === 'asset' && cssExtensions.test(fileName)
          && entryNames.has(fileName.replace(/\.[^.]+$/, ''))

        if (isEntryJs) {
          // JS entries are built as _[name]-[hash].js (content-hashed).
          // Write a thin shim as [name].js for the asset pipeline so that
          // Propshaft/Sprockets can serve it via javascript_include_tag.
          //
          // Why: Propshaft digests entry filenames (inertia.js → inertia-abc123.js)
          // but cannot rewrite import paths inside Vite's chunks. Without the shim,
          // the <script> tag and chunk imports resolve to different ES module
          // instances — duplicating React, Inertia, and other stateful singletons.
          // The shim ensures both paths chain to the same _[name]-[hash].js module.
          const shimName = (chunk as { name: string }).name + '.js'
          const shim = `import "./${fileName}";export * from "./${fileName}";\n`
          fs.writeFileSync(path.join(outDir, shimName), shim)
          fs.writeFileSync(path.join(assetPipelineDir, shimName), shim)
        } else if (isEntryCss) {
          // Copy entry CSS to the asset pipeline. Shared chunk CSS stays in outputDir.
          const src = path.join(outDir, fileName)
          const dest = path.join(assetPipelineDir, fileName)
          fs.mkdirSync(path.dirname(dest), { recursive: true })
          fs.copyFileSync(src, dest)
        }
      }
    },

    transform(code) {
      return replaceOriginPlaceholder(code, devServerUrl)
    },

    configureServer(server) {
      let syncTimer: ReturnType<typeof setTimeout> | null = null

      // Re-discover entries from the entrypoints dir and regenerate all stubs.
      // Called on initial listen and whenever entrypoint files are added/removed.
      const syncStubs = () => {
        if (!devServerUrl) return
        const freshInput = epDir ? discoverEntrypointInputs(sourceDir, epDir) : input
        const freshEntries = resolveEntries(freshInput, sourceDir)

        // Clear old stubs
        for (const stub of writtenStubs) {
          fs.rmSync(stub, { force: true })
        }
        writtenStubs.length = 0

        writeDevStubs(freshEntries, assetPipelineDir, devServerUrl, reactRefresh, writtenStubs)
      }

      // Debounced version for watcher events — collapses burst operations
      // (e.g., pasting multiple files, git checkout) into a single rescan.
      const debouncedSyncStubs = () => {
        if (syncTimer) clearTimeout(syncTimer)
        syncTimer = setTimeout(syncStubs, 100)
      }

      // Write placeholder stubs so Propshaft/Sprockets can discover asset files
      // at boot time, before the Vite dev server is ready with its URL.
      // Only write when httpServer exists — skip for embedded Vite instances
      // (e.g., Storybook) that would otherwise overwrite real dev stubs.
      if (server.httpServer && !server.httpServer.listening) {
        writePlaceholderStubs(entries, assetPipelineDir, writtenStubs)
      }

      server.httpServer?.once('listening', () => {
        const address = server.httpServer?.address()

        if (isAddressInfo(address)) {
          devServerUrl = resolveDevServerUrl(address, resolvedConfig)

          syncStubs()

          // Write dev meta file for progressive upgrade to the rails_vite gem
          if (devMetaPath) {
            const meta: Record<string, unknown> = { url: devServerUrl, sourceDir }
            if (epDir) meta.entrypointsDir = epDir
            if (reactRefresh) meta.reactRefresh = true
            meta.jsbundling = true
            fs.mkdirSync(path.dirname(devMetaPath), { recursive: true })
            fs.writeFileSync(devMetaPath, JSON.stringify(meta))
          }

          // Watch entrypoints dir for new/removed files and regenerate stubs
          if (epDir) {
            const epAbsDir = path.resolve(sourceDir, epDir)
            server.watcher.add(epAbsDir)
            const epAbsDirPrefix = epAbsDir + '/'
            server.watcher.on('add', (filePath: string) => {
              if (filePath.startsWith(epAbsDirPrefix) && isEntrypointFile(filePath)) {
                server.config.logger.info(`  RAILS  new entrypoint: ${path.relative(sourceDir, filePath)}`)
                debouncedSyncStubs()
              }
            })
            server.watcher.on('unlink', (filePath: string) => {
              if (filePath.startsWith(epAbsDirPrefix) && isEntrypointFile(filePath)) {
                server.config.logger.info(`  RAILS  removed entrypoint: ${path.relative(sourceDir, filePath)}`)
                debouncedSyncStubs()
              }
            })
          }

          server.config.logger.info(
            `\n  RAILS  rails-vite-plugin/jsbundling → ${assetPipelineDir}`
          )
        }
      })

      bindExitHandler(() => {
        for (const stub of writtenStubs) {
          fs.rmSync(stub, { force: true })
        }
        writtenStubs.length = 0
        if (devMetaPath) {
          fs.rmSync(devMetaPath, { force: true })
        }
      })

      // Watch view templates for full-page reload
      const resolvedRefreshPaths = resolveRefreshPaths(options.refresh)
      if (resolvedRefreshPaths.length) {
        const match = picomatch(resolvedRefreshPaths)
        server.watcher.add(resolvedRefreshPaths)
        server.watcher.on('change', (filePath: string) => {
          const relativePath = path.relative(process.cwd(), filePath)
          if (match(relativePath)) {
            server.hot.send({ type: 'full-reload', path: '*' })
          }
        })
      }

      const devServerIndexHtml = readDevServerIndexHtml()

      return () =>
        server.middlewares.use((req, res, next) => {
          if (req.url === '/index.html') {
            res.statusCode = 404
            res.setHeader('Content-Type', 'text/html')
            res.end(devServerIndexHtml)
            return
          }
          next()
        })
    },
  }
}

function resolveSsrConfig(
  ssr: JsbundlingOptions['ssr'],
  sourceDir: string,
  outputDir: string,
): { entry: string; outDir: string } | null {
  if (!ssr) return null
  const entry = typeof ssr === 'string' ? ssr : ssr.entry
  const outDir = (typeof ssr === 'object' ? ssr.outDir : undefined) ?? outputDir + '-ssr'
  return {
    entry: prefixWithSourceDir(entry, sourceDir),
    outDir,
  }
}

/**
 * Write placeholder stubs so Propshaft/Sprockets can discover asset files
 * at boot time, before the Vite dev server is ready with its URL.
 * Writes unconditionally — stubs are overwritten by writeDevStubs once the server is listening.
 */
function writePlaceholderStubs(
  entries: ResolvedEntry[],
  outDir: string,
  writtenStubs: string[],
): void {
  fs.mkdirSync(outDir, { recursive: true })

  const seen = new Set<string>()
  for (const { name } of entries) {
    if (seen.has(name)) continue
    seen.add(name)

    const jsStub = path.join(outDir, `${name}.js`)
    fs.mkdirSync(path.dirname(jsStub), { recursive: true })
    fs.writeFileSync(jsStub, '// rails-vite placeholder – loading…\n')
    writtenStubs.push(jsStub)

    const cssStub = path.join(outDir, `${name}.css`)
    fs.writeFileSync(cssStub, '/* rails-vite placeholder – loading… */\n')
    writtenStubs.push(cssStub)
  }
}

function writeDevStubs(
  entries: ResolvedEntry[],
  outDir: string,
  devServerUrl: string,
  reactRefresh: boolean,
  writtenStubs: string[],
): void {
  fs.mkdirSync(outDir, { recursive: true })

  const importLine = (url: string) =>
    reactRefresh ? `await import("${url}");` : `import "${url}";`

  const jsEntries = entries.filter(e => !cssExtensions.test(e.sourcePath))
  const cssEntries = entries.filter(e => cssExtensions.test(e.sourcePath))

  // JS stubs: import @vite/client + all CSS entries (for HMR) + the JS entry itself.
  for (const { name, sourcePath } of jsEntries) {
    const stubPath = path.join(outDir, `${name}.js`)
    fs.mkdirSync(path.dirname(stubPath), { recursive: true })
    const lines = ['// rails-vite dev stub – DO NOT EDIT']
    if (reactRefresh) {
      // Static import for the refresh runtime — just exports a function, safe to hoist.
      // Everything else uses dynamic import() so the preamble executes first
      // (static imports hoist, so injectIntoGlobalHook would run after all modules).
      lines.push(`import { injectIntoGlobalHook } from "${devServerUrl}/@react-refresh";`)
      lines.push('injectIntoGlobalHook(window);')
      lines.push('window.$RefreshReg$ = () => {};')
      lines.push('window.$RefreshSig$ = () => (type) => type;')
    }
    lines.push(importLine(`${devServerUrl}/@vite/client`))
    // Import CSS entries so Vite's module graph tracks them for HMR
    for (const { sourcePath: cssPath } of cssEntries) {
      lines.push(importLine(`${devServerUrl}/${cssPath}`))
    }
    lines.push(importLine(`${devServerUrl}/${sourcePath}`))
    fs.writeFileSync(stubPath, lines.join('\n') + '\n')
    writtenStubs.push(stubPath)
  }

  // Empty CSS stubs so stylesheet_link_tag doesn't error.
  // Actual CSS is injected by @vite/client through the JS imports above.
  const seen = new Set<string>()
  for (const { name } of entries) {
    if (seen.has(name)) continue
    seen.add(name)
    const cssStubPath = path.join(outDir, `${name}.css`)
    fs.mkdirSync(path.dirname(cssStubPath), { recursive: true })
    fs.writeFileSync(cssStubPath, '/* rails-vite dev stub */\n')
    writtenStubs.push(cssStubPath)
  }
}
