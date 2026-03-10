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
