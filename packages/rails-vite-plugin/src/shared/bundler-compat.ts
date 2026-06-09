import type { UserConfig } from 'vite'

// Vite 8 (Rolldown) uses `rolldownOptions` instead of `rollupOptions`.
// Detect at runtime to support both Vite 7 and 8.
export function resolveBundlerOptionsKey(meta: { rolldownVersion?: string }): 'rolldownOptions' | 'rollupOptions' {
  return meta?.rolldownVersion ? 'rolldownOptions' : 'rollupOptions'
}

export function getUserBundlerInput(userConfig: UserConfig): unknown {
  // @ts-expect-error -- `rolldownOptions` exists in Vite 8+ only
  return userConfig.build?.rolldownOptions?.input ?? userConfig.build?.rollupOptions?.input
}

export function getResolvedBundlerInput(buildConfig: { rollupOptions?: { input?: unknown } }): unknown {
  const config = buildConfig as { rolldownOptions?: { input?: unknown }, rollupOptions?: { input?: unknown } }
  return config.rolldownOptions?.input ?? config.rollupOptions?.input
}

export function normalizeBundlerInput(input: unknown): string[] {
  if (typeof input === 'string') return [input]
  if (Array.isArray(input)) return input.filter((entry): entry is string => typeof entry === 'string')
  if (input && typeof input === 'object') {
    return Object.values(input).filter((entry): entry is string => typeof entry === 'string')
  }
  return []
}
