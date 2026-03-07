import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'
import { AddressInfo } from 'net'
import picomatch from 'picomatch'
import {
  Plugin,
  UserConfig,
  ConfigEnv,
  ResolvedConfig,
  loadEnv,
  defaultAllowedOrigins,
} from 'vite'

export type InputOption = string | string[] | Record<string, string>

export interface RailsViteOptions {
  input?: InputOption
  sourceDir?: string
  ssr?: InputOption
  ssrOutputDirectory?: string
  devMetaFile?: string
  buildDirectory?: string
  publicDirectory?: string
  refresh?: boolean | string | string[]
}

type DevServerUrl = `${'http' | 'https'}://${string}:${number}`

export const refreshPaths = [
  'app/views/**/*.{erb,slim,haml}',
  'app/helpers/**/*.rb',
]

let exitHandlersBound = false

export default function rails(options: RailsViteOptions = {}): Plugin {
  const sourceDir = options.sourceDir ?? 'app/javascript'
  const input = options.input ?? detectEntrypoint(sourceDir)
  const publicDirectory = options.publicDirectory ?? 'public'
  const buildDirectory = options.buildDirectory ?? 'vite'
  const devMetaPath = options.devMetaFile ?? path.join('tmp', 'rails-vite.json')
  const ssrOutputDirectory = options.ssrOutputDirectory ?? 'ssr'

  const resolvedInput = resolveInput(input, sourceDir)
  const resolvedSsr = options.ssr !== undefined ? resolveInput(options.ssr, sourceDir) : undefined

  let resolvedConfig: ResolvedConfig
  let reactRefresh = false

  return {
    name: 'rails-vite',
    enforce: 'post',

    config(userConfig: UserConfig, { command, mode }: ConfigEnv): UserConfig {
      const env = loadEnv(mode, userConfig.envDir || process.cwd(), '')
      const ssr = !!userConfig.build?.ssr

      ensureCommandShouldRunInEnvironment(command, env)

      return {
        base: userConfig.base ?? (command === 'build' ? `/${buildDirectory}/` : ''),
        publicDir: userConfig.publicDir ?? false,
        build: {
          manifest: userConfig.build?.manifest ?? (ssr ? false : 'manifest.json'),
          ssrManifest: userConfig.build?.ssrManifest ?? (ssr ? 'ssr-manifest.json' : false),
          outDir: userConfig.build?.outDir ?? (ssr ? ssrOutputDirectory : path.join(publicDirectory, buildDirectory)),
          rollupOptions: {
            input: userConfig.build?.rollupOptions?.input ?? (ssr ? resolvedSsr : resolvedInput),
          },
          assetsInlineLimit: userConfig.build?.assetsInlineLimit ?? 0,
        },
        server: {
          cors: userConfig.server?.cors ?? {
            origin: userConfig.server?.origin ?? defaultAllowedOrigins,
          },
        },
        resolve: {
          alias: Array.isArray(userConfig.resolve?.alias)
            ? [
                ...(userConfig.resolve?.alias ?? []),
                { find: '@', replacement: path.resolve(process.cwd(), sourceDir) },
              ]
            : {
                '@': path.resolve(process.cwd(), sourceDir),
                ...(userConfig.resolve?.alias as Record<string, string> | undefined),
              },
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
      fs.writeFileSync(
        path.join(outDir, 'rails-vite.json'),
        JSON.stringify({ sourceDir })
      )
    },

    configureServer(server) {
      server.httpServer?.once('listening', () => {
        const address = server.httpServer?.address()

        if (isAddressInfo(address)) {
          const devServerUrl = resolveDevServerUrl(address, resolvedConfig)
          resolvedConfig.server.origin = devServerUrl

          const meta: Record<string, unknown> = { url: devServerUrl, sourceDir }
          if (reactRefresh) meta.reactRefresh = true
          fs.writeFileSync(devMetaPath, JSON.stringify(meta))

          setTimeout(() => {
            server.config.logger.info(
              `\n  RAILS  rails-vite-plugin`
            )
          }, 100)
        }
      })

      if (!exitHandlersBound) {
        const clean = () => {
          fs.rmSync(devMetaPath, { force: true })
        }

        process.on('exit', clean)
        process.on('SIGINT', () => process.exit())
        process.on('SIGTERM', () => process.exit())
        process.on('SIGHUP', () => process.exit())

        exitHandlersBound = true
      }

      // Watch view templates for full-page reload
      const resolvedRefreshPaths = resolveRefreshPaths(options.refresh)
      if (resolvedRefreshPaths.length) {
        const match = picomatch(resolvedRefreshPaths)
        server.watcher.add(resolvedRefreshPaths)
        server.watcher.on('change', (filePath: string) => {
          const relativePath = path.relative(process.cwd(), filePath)
          if (match(relativePath)) {
            server.ws.send({ type: 'full-reload', path: '*' })
          }
        })
      }

      // Serve a helpful page at the dev server root
      const devServerIndexHtml = fs.readFileSync(
        path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', 'dev-server-index.html'),
        'utf-8'
      )

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

function resolveInput(
  input: InputOption,
  sourceDir: string
): InputOption {
  if (typeof input === 'object' && !Array.isArray(input)) {
    return Object.fromEntries(
      Object.entries(input).map(([key, value]) => [key, prefixWithSourceDir(value, sourceDir)])
    )
  }
  if (Array.isArray(input)) {
    return input.map((entry) => prefixWithSourceDir(entry, sourceDir))
  }
  return prefixWithSourceDir(input, sourceDir)
}

function prefixWithSourceDir(entry: string, sourceDir: string): string {
  if (entry.startsWith(sourceDir + '/') || entry.startsWith('/')) {
    return entry
  }
  return `${sourceDir}/${entry}`
}

const entrypointExtensions = /\.(mjs|js|mts|ts|jsx|tsx|css|scss|sass|less|styl|pcss)$/

function detectEntrypoint(sourceDir: string): string | string[] {
  const entrypointsDir = path.join(sourceDir, 'entrypoints')
  if (fs.existsSync(entrypointsDir)) {
    return discoverEntrypoints(entrypointsDir).map(
      (entry) => `entrypoints/${entry}`
    )
  }

  for (const ext of ['.js', '.mjs', '.ts', '.mts', '.jsx', '.tsx']) {
    const candidate = path.join(sourceDir, `application${ext}`)
    if (fs.existsSync(candidate)) {
      return `application${ext}`
    }
  }
  return 'application.js'
}

function discoverEntrypoints(dir: string, base: string = dir): string[] {
  const entries: string[] = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      entries.push(...discoverEntrypoints(path.join(dir, entry.name), base))
    } else if (entrypointExtensions.test(entry.name)) {
      entries.push(path.relative(base, path.join(dir, entry.name)))
    }
  }
  return entries
}

function resolveRefreshPaths(
  refresh: RailsViteOptions['refresh']
): string[] {
  if (refresh === false) return []
  if (!refresh || refresh === true) return refreshPaths
  if (typeof refresh === 'string') return [refresh]
  return refresh
}

function resolveDevServerUrl(
  address: AddressInfo,
  config: ResolvedConfig
): DevServerUrl {
  const hmr = typeof config.server.hmr === 'object' ? config.server.hmr : null

  const clientProtocol = hmr?.protocol
    ? hmr.protocol === 'wss'
      ? 'https'
      : 'http'
    : null
  const serverProtocol = config.server.https ? 'https' : 'http'
  const protocol = clientProtocol ?? serverProtocol

  const configHost =
    typeof config.server.host === 'string' ? config.server.host : null
  const serverAddress =
    address.family === 'IPv6' || (address.family as unknown) === 6
      ? `[${address.address}]`
      : address.address
  const host = hmr?.host ?? configHost ?? serverAddress

  const port = hmr?.clientPort ?? address.port

  return `${protocol}://${host}:${port}`
}

function isAddressInfo(
  x: string | AddressInfo | null | undefined
): x is AddressInfo {
  return typeof x === 'object' && x !== null
}

function ensureCommandShouldRunInEnvironment(
  command: string,
  env: Record<string, string>
): void {
  if (command === 'build') {
    return
  }

  if (env.CI !== undefined) {
    throw new Error(
      'rails-vite-plugin: You should not run the Vite dev server in CI. ' +
        'Run `rake vite:build` instead.'
    )
  }

  if (env.RAILS_ENV === 'production') {
    throw new Error(
      'rails-vite-plugin: You should not run the Vite dev server in production. ' +
        'Run `rake vite:build` instead.'
    )
  }
}

function resolveNoExternal(
  config: UserConfig
): true | Array<string | RegExp> {
  const userNoExternal = (config.ssr as { noExternal?: true | Array<string | RegExp> } | undefined)?.noExternal
  const pluginNoExternal = ['rails-vite-plugin']

  if (userNoExternal === true) {
    return true
  }

  if (userNoExternal === undefined) {
    return pluginNoExternal
  }

  return [
    ...(Array.isArray(userNoExternal) ? userNoExternal : [userNoExternal]),
    ...pluginNoExternal,
  ]
}
