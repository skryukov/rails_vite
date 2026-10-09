import path from 'path'
import picomatch from 'picomatch'

export const refreshPaths = [
  'app/views/**/*.{erb,slim,haml}',
  'app/helpers/**/*.rb',
]

export function resolveRefreshPaths(
  refresh: boolean | string | string[] | undefined
): string[] {
  if (refresh === false) return []
  if (!refresh || refresh === true) return refreshPaths
  if (typeof refresh === 'string') return [refresh]
  return refresh
}

// Vite's watcher has globbing disabled, so watch the static base of each glob instead.
export function resolveRefreshWatchPaths(patterns: string[]): string[] {
  return patterns.map((pattern) => path.resolve(picomatch.scan(pattern).base))
}
