import type { UserConfig } from 'vite'

export function resolveNoExternal(
  config: UserConfig
): true | Array<string | RegExp> {
  const userNoExternal = config.ssr?.noExternal
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
