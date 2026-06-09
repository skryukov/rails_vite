import fs from 'fs'
import path from 'path'
import picomatch from 'picomatch'
import type { InputOption, ResolvedEntry } from './types.js'
import { cssExtensionList } from './css.js'

const jsExtensions = ['mjs', 'js', 'mts', 'ts', 'jsx', 'tsx']
const entrypointExtensions = new RegExp(`\\.(${[...jsExtensions, ...cssExtensionList].join('|')})$`)

export function isEntrypointFile(filePath: string): boolean {
  return entrypointExtensions.test(filePath)
}

export function resolveEntries(input: InputOption, sourceDir: string): ResolvedEntry[] {
  if (typeof input === 'object' && !Array.isArray(input)) {
    return Object.entries(input).map(([name, value]) => ({
      name,
      sourcePath: prefixWithSourceDir(value, sourceDir),
    }))
  }

  const rawInputs = Array.isArray(input) ? input : [input]
  const inputs = rawInputs.flatMap(entry => expandGlob(entry, sourceDir))
  const sourcePaths = inputs.map(entry => prefixWithSourceDir(entry, sourceDir))
  const commonPrefix = detectCommonEntryPrefix(sourcePaths, sourceDir)

  return sourcePaths.map(sourcePath => ({
    name: entrypointName(sourcePath, sourceDir, commonPrefix),
    sourcePath,
  }))
}

/**
 * Convert resolved entries to Rollup-compatible input.
 * Array form for string/array inputs; object form preserves explicit user names.
 */
export function entriesToRollupInput(entries: ResolvedEntry[], isNamedInput: boolean): InputOption {
  if (isNamedInput) {
    return Object.fromEntries(entries.map(e => [e.name, e.sourcePath]))
  }
  if (entries.length === 1) return entries[0].sourcePath
  return entries.map(e => e.sourcePath)
}

export function resolveInput(input: InputOption, sourceDir: string): InputOption {
  if (typeof input === 'object' && !Array.isArray(input)) {
    return Object.fromEntries(
      Object.entries(input).map(([key, value]) => [key, prefixWithSourceDir(value, sourceDir)])
    )
  }
  if (Array.isArray(input)) {
    return input.map((entry) => prefixWithSourceDir(entry, sourceDir))
  }
  return prefixWithSourceDir(input, sourceDir)
}

export function prefixWithSourceDir(entry: string, sourceDir: string): string {
  if (entry.startsWith(sourceDir + '/') || entry.startsWith('/')) {
    return entry
  }
  return `${sourceDir}/${entry}`
}

/**
 * The sourceDir prefix the Rails helpers should prepend to manifest entries.
 * Empty when `prependSourceDirToEntries` is false (Vite's `root` is the sourceDir,
 * so entries are already root-relative). `=== false` keeps the default `true` when
 * the option is omitted.
 */
export function resolveManifestSourceDir(sourceDir: string, prependSourceDirToEntries: boolean | undefined): string {
  return prependSourceDirToEntries === false ? '' : sourceDir
}

export function detectEntrypointsDir(sourceDir: string): string | null {
  const entrypointsDir = path.join(sourceDir, 'entrypoints')
  return fs.existsSync(entrypointsDir) ? 'entrypoints' : null
}

export function discoverEntrypointInputs(sourceDir: string, entrypointsDir: string): string[] {
  const absDir = path.join(sourceDir, entrypointsDir)
  return discoverEntrypoints(absDir).map(
    (entry) => `${entrypointsDir}/${entry}`
  )
}

export function detectEntrypoint(sourceDir: string): string {
  for (const ext of ['.js', '.mjs', '.ts', '.mts', '.jsx', '.tsx']) {
    const candidate = path.join(sourceDir, `application${ext}`)
    if (fs.existsSync(candidate)) {
      return `application${ext}`
    }
  }
  return 'application.js'
}

function isGlob(pattern: string): boolean {
  return /[*?{]/.test(pattern)
}

function expandGlob(entry: string, sourceDir: string): string[] {
  if (!isGlob(entry)) return [entry]

  const matcher = picomatch(entry)

  if (entry.includes('**')) {
    // Recursive: find the static prefix directory, then walk it
    const parts = entry.split('/')
    const staticParts = []
    for (const part of parts) {
      if (isGlob(part)) break
      staticParts.push(part)
    }
    const baseDir = staticParts.length > 0
      ? path.join(sourceDir, ...staticParts)
      : sourceDir
    if (!fs.existsSync(baseDir)) return []

    return walkDir(baseDir, sourceDir).filter(f => matcher(f))
  }

  // Non-recursive: single directory match
  const dir = path.join(sourceDir, path.dirname(entry))
  const pattern = path.basename(entry)
  const fileMatcher = picomatch(pattern)

  if (!fs.existsSync(dir)) return []

  return fs.readdirSync(dir, { withFileTypes: true })
    .filter(f => f.isFile() && fileMatcher(f.name))
    .map(f => path.relative(sourceDir, path.join(dir, f.name)))
}

function walkDir(dir: string, baseDir: string): string[] {
  const results: string[] = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      results.push(...walkDir(full, baseDir))
    } else if (entry.isFile()) {
      results.push(path.relative(baseDir, full))
    }
  }
  return results
}

function discoverEntrypoints(dir: string, base: string = dir): string[] {
  const entries: string[] = []
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      entries.push(...discoverEntrypoints(path.join(dir, entry.name), base))
    } else if (entrypointExtensions.test(entry.name)) {
      entries.push(path.relative(base, path.join(dir, entry.name)))
    }
  }
  return entries
}

function entrypointName(sourcePath: string, sourceDir: string, commonPrefix: string | null): string {
  let name = sourcePath
  if (name.startsWith(sourceDir + '/')) {
    name = name.slice(sourceDir.length + 1)
  }
  if (commonPrefix && name.startsWith(commonPrefix + '/')) {
    name = name.slice(commonPrefix.length + 1)
  }
  return name.replace(/\.[^.]+$/, '')
}

/**
 * Detect the common directory prefix among all input entries (after stripping sourceDir).
 * This mirrors how Rollup computes entry chunk names and ensures dev stubs match build output.
 */
function detectCommonEntryPrefix(sourcePaths: string[], sourceDir: string): string | null {
  if (sourcePaths.length === 0) return null

  const dirs = sourcePaths.map((entry) => {
    let name = entry
    if (name.startsWith(sourceDir + '/')) {
      name = name.slice(sourceDir.length + 1)
    }
    const dir = path.dirname(name)
    return dir === '.' ? '' : dir
  })

  const first = dirs[0]
  if (!first) return null
  if (dirs.every((d) => d === first || d.startsWith(first + '/'))) {
    return first
  }

  const parts = first.split('/')
  let common = ''
  for (const part of parts) {
    const candidate = common ? `${common}/${part}` : part
    if (dirs.every((d) => d === candidate || d.startsWith(candidate + '/'))) {
      common = candidate
    } else {
      break
    }
  }

  return common || null
}
