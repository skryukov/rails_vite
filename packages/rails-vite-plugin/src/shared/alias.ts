import path from 'path'
import type { AliasOptions } from 'vite'

export function resolveAlias(userAlias: AliasOptions | undefined, sourceDir: string): AliasOptions {
  const atReplacement = path.resolve(process.cwd(), sourceDir)

  if (Array.isArray(userAlias)) {
    const hasAt = userAlias.some(a => a.find === '@')
    return hasAt ? userAlias : [...userAlias, { find: '@', replacement: atReplacement }]
  }

  return {
    '@': atReplacement,
    ...(userAlias as Record<string, string> | undefined),
  }
}
