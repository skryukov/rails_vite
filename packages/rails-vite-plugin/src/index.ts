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

import type { InputOption } from './shared/types.js'
import { ORIGIN_PLACEHOLDER } from './shared/types.js'
import { resolveInput, detectEntrypointsDir, discoverEntrypointInputs, detectEntrypoint } from './shared/entries.js'
import { resolveAlias } from './shared/alias.js'
import { resolveDevServerUrl, isAddressInfo, replaceOriginPlaceholder } from './shared/dev-server.js'
import { resolveBundlerOptionsKey, getUserBundlerInput, getResolvedBundlerInput, normalizeBundlerInput } from './shared/bundler-compat.js'
import { ensureCommandShouldRunInEnvironment } from './shared/env-guard.js'
import { refreshPaths, resolveRefreshPaths } from './shared/refresh.js'
import { readDevServerIndexHtml } from './shared/dev-server-page.js'
import { resolveNoExternal } from './shared/ssr.js'
import { bindExitHandler, removeOwnedFile } from './shared/cleanup.js'

export type { InputOption }
export { refreshPaths }

export interface RailsViteOptions {
  input?: InputOption
  sourceDir?: string
  ssr?: InputOption
  ssrOutDir?: string
  devMetaFile?: string
  /** Directory name under publicDir for Vite build output (default: 'vite') */
  buildDir?: string
  /** Public directory (default: 'public') */
  publicDir?: string
  refresh?: boolean | string | string[]
}

export default function rails(options: RailsViteOptions = {}): Plugin {
  const sourceDir = options.sourceDir ?? 'app/javascript'
  const entrypointsDir = options.input === undefined ? detectEntrypointsDir(sourceDir) : null
  const input = options.input ?? (entrypointsDir ? discoverEntrypointInputs(sourceDir, entrypointsDir) : detectEntrypoint(sourceDir))
  const publicDir = options.publicDir ?? 'public'
  const userBuildDir = options.buildDir
  const devMetaPath = options.devMetaFile ?? path.join('tmp', 'rails-vite.json')
  const ssrOutDir = options.ssrOutDir ?? 'ssr'

  const resolvedInput = resolveInput(input, sourceDir)
  const resolvedSsr = options.ssr !== undefined ? resolveInput(options.ssr, sourceDir) : undefined

  let resolvedConfig: ResolvedConfig
  let reactRefresh = false
  let devServerUrl: string | null = null
  let effectiveBuildDir: string
  let devServerEnv: Record<string, string> = {}

  return {
    name: 'rails-vite',
    enforce: 'post',

    config(userConfig: UserConfig, { command, mode, isSsrBuild }: ConfigEnv): UserConfig {
      devServerEnv = loadEnv(mode, userConfig.envDir || process.cwd(), '')

      // @ts-expect-error -- `this.meta.rolldownVersion` exists in Vite 8+
      const bundlerOptionsKey = resolveBundlerOptionsKey(this.meta)
      const userBundlerInput = getUserBundlerInput(userConfig)

      effectiveBuildDir = userBuildDir ?? (mode === 'test' ? 'vite-test' : 'vite')

      return {
        base: userConfig.base ?? (command === 'build' ? `/${effectiveBuildDir}/` : ''),
        publicDir: userConfig.publicDir ?? false,
        build: {
          manifest: userConfig.build?.manifest ?? (isSsrBuild ? false : 'manifest.json'),
          ssrManifest: userConfig.build?.ssrManifest ?? (isSsrBuild ? 'ssr-manifest.json' : false),
          outDir: userConfig.build?.outDir ?? (isSsrBuild ? ssrOutDir : path.join(publicDir, effectiveBuildDir)),
          [bundlerOptionsKey]: {
            input: userBundlerInput ?? (isSsrBuild ? resolvedSsr : resolvedInput),
          },
          assetsInlineLimit: userConfig.build?.assetsInlineLimit ?? 0,
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

    writeBundle() {
      if (resolvedConfig.build.ssr) return

      const outDir = resolvedConfig.build.outDir
      const meta: Record<string, unknown> = { sourceDir, buildDir: effectiveBuildDir }
      const buildInputs = normalizeBundlerInput(getResolvedBundlerInput(resolvedConfig.build))
      if (buildInputs.length) meta.buildInputs = buildInputs
      if (entrypointsDir) meta.entrypointsDir = entrypointsDir
      if (resolvedSsr) meta.ssrOutputDir = ssrOutDir
      fs.writeFileSync(path.join(outDir, 'rails-vite.json'), JSON.stringify(meta))
    },

    transform(code) {
      return replaceOriginPlaceholder(code, devServerUrl)
    },

    configureServer(server) {
      ensureCommandShouldRunInEnvironment('serve', devServerEnv, 'rails-vite-plugin')

      server.httpServer?.once('listening', () => {
        const address = server.httpServer?.address()

        if (isAddressInfo(address)) {
          devServerUrl = resolveDevServerUrl(address, resolvedConfig)

          const meta: Record<string, unknown> = { url: devServerUrl, sourceDir, buildDir: effectiveBuildDir, pid: process.pid }
          if (entrypointsDir) meta.entrypointsDir = entrypointsDir
          if (resolvedSsr) meta.ssrOutputDir = ssrOutDir
          if (reactRefresh) meta.reactRefresh = true
          fs.writeFileSync(devMetaPath, JSON.stringify(meta))

          bindExitHandler(() => {
            removeOwnedFile(devMetaPath)
          })

          setTimeout(() => {
            server.config.logger.info(
              `\n  RAILS  rails-vite-plugin`
            )
          }, 100)
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
            res.end(devServerIndexHtml)
            return
          }
          next()
        })
    },
  }
}
