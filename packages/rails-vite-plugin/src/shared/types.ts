export type InputOption = string | string[] | Record<string, string>

export type DevServerUrl = `${'http' | 'https'}://${string}:${number}`

// Placeholder URL used as `server.origin` during config resolution.
// Replaced with the real dev server URL once the server starts listening.
export const ORIGIN_PLACEHOLDER = 'http://__rails_vite_placeholder__.test'

export interface ResolvedEntry {
  /** Output name (e.g., 'application', 'admin/index') */
  name: string
  /** Full path relative to project root */
  sourcePath: string
}
