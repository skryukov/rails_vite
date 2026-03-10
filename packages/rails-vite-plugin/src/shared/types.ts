export type InputOption = string | string[] | Record<string, string>

export type DevServerUrl = `${'http' | 'https'}://${string}:${number}`

export interface ResolvedEntry {
  /** Output name (e.g., 'application', 'admin/index') */
  name: string
  /** Full path relative to project root */
  sourcePath: string
}
