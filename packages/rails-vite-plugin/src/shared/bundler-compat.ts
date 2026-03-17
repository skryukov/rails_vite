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
