import { AddressInfo } from 'net'
import type { ResolvedConfig } from 'vite'
import type { DevServerUrl } from './types.js'
import { ORIGIN_PLACEHOLDER } from './types.js'

export function resolveDevServerUrl(
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

export function isAddressInfo(
  x: string | AddressInfo | null | undefined
): x is AddressInfo {
  return typeof x === 'object' && x !== null
}

export function replaceOriginPlaceholder(code: string, devServerUrl: string | null): string | undefined {
  if (devServerUrl && code.includes(ORIGIN_PLACEHOLDER)) {
    return code.replaceAll(ORIGIN_PLACEHOLDER, devServerUrl)
  }
}
