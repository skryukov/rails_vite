import fs from 'fs'

let exitHandlersBound = false

/**
 * Register a cleanup function that runs on process exit.
 * Signal handlers are only registered once per process to avoid duplicates.
 */
export function bindExitHandler(cleanupFn: () => void): void {
  process.on('exit', cleanupFn)

  if (!exitHandlersBound) {
    process.on('SIGINT', () => process.exit())
    process.on('SIGTERM', () => process.exit())
    process.on('SIGHUP', () => process.exit())
    exitHandlersBound = true
  }
}

export function removeOwnedFile(filePath: string, pid = process.pid): void {
  let ownerPid: unknown

  try {
    ownerPid = JSON.parse(fs.readFileSync(filePath, 'utf8')).pid
  } catch {
    return
  }

  if (ownerPid === pid) {
    fs.rmSync(filePath, { force: true })
  }
}
