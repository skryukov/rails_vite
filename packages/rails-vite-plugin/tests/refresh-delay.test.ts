import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import path from 'path'
import type { ConfigEnv, Plugin, UserConfig } from 'vite'
import rails from '../src'
import jsbundling from '../src/jsbundling'

const SERVE: ConfigEnv = { command: 'serve', mode: 'development' }
const VIEW = path.resolve('app/views/users/show.html.erb')
const FULL_RELOAD = { type: 'full-reload', path: '*' }

vi.mock('../src/shared/cleanup.js', () => ({
  bindExitHandler: vi.fn(),
}))

function startServer(plugin: Plugin) {
  const changeListeners: ((filePath: string) => void)[] = []
  // No httpServer, so the plugins write no dev metadata or stubs.
  const server = {
    watcher: {
      add: vi.fn(),
      on: (event: string, cb: (filePath: string) => void) => {
        if (event === 'change') changeListeners.push(cb)
      },
    },
    config: { logger: { info: vi.fn() } },
    hot: { send: vi.fn() },
    middlewares: { use: vi.fn() },
  }

  ;(plugin.config as (config: UserConfig, env: ConfigEnv) => UserConfig)({}, SERVE)
  ;(plugin.configureServer as unknown as (server: unknown) => unknown)(server)

  return {
    send: server.hot.send,
    change: (filePath: string) => changeListeners.forEach((cb) => cb(filePath)),
    close: () => (plugin.closeBundle as () => void)(),
  }
}

describe.each([
  ['rails', (refreshDelay?: number) => rails({ input: 'application.js', refreshDelay })],
  ['jsbundling', (refreshDelay?: number) => jsbundling({ input: 'application.js', refreshDelay })],
])('%s refreshDelay', (_, createPlugin) => {
  beforeEach(() => {
    vi.stubEnv('CI', undefined)
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.unstubAllEnvs()
    vi.useRealTimers()
  })

  it('sends a full reload at once without a delay', () => {
    const { send, change } = startServer(createPlugin())

    change(VIEW)
    change(VIEW)

    expect(send).toHaveBeenCalledTimes(2)
    expect(send).toHaveBeenCalledWith(FULL_RELOAD)
  })

  it('sends a full reload after the delay', () => {
    const { send, change } = startServer(createPlugin(300))

    change(VIEW)
    vi.advanceTimersByTime(299)
    expect(send).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(send).toHaveBeenCalledExactlyOnceWith(FULL_RELOAD)
  })

  it('sends one full reload for a burst of changes', () => {
    const { send, change } = startServer(createPlugin(300))

    change(VIEW)
    vi.advanceTimersByTime(200)
    change(path.resolve('app/helpers/users_helper.rb'))
    vi.advanceTimersByTime(299)
    expect(send).not.toHaveBeenCalled()

    vi.advanceTimersByTime(1)
    expect(send).toHaveBeenCalledExactlyOnceWith(FULL_RELOAD)
  })

  it('sends nothing for files outside the refresh paths', () => {
    const { send, change } = startServer(createPlugin(300))

    change(path.resolve('app/models/user.rb'))
    vi.runAllTimers()

    expect(send).not.toHaveBeenCalled()
  })

  it('cancels a pending full reload when the server closes', () => {
    const { send, change, close } = startServer(createPlugin(300))

    change(VIEW)
    close()
    vi.runAllTimers()

    expect(send).not.toHaveBeenCalled()
  })
})
