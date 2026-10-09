import type { ViteDevServer } from 'vite'

/**
 * Sends a full-page reload `delay` ms after the last change, so a burst of
 * change events sends one reload. With a delay of 0, it sends the reload at once.
 */
export function createFullReload(delay: number) {
  let timer: ReturnType<typeof setTimeout> | undefined

  return {
    send(server: Pick<ViteDevServer, 'hot'>): void {
      const reload = () => server.hot.send({ type: 'full-reload', path: '*' })
      if (delay <= 0) return reload()

      clearTimeout(timer)
      timer = setTimeout(reload, delay)
    },
    cancel(): void {
      clearTimeout(timer)
    },
  }
}
