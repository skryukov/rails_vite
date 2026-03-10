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
