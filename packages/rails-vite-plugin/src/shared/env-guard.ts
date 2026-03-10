export function ensureCommandShouldRunInEnvironment(
  command: string,
  env: Record<string, string>,
  pluginName: string,
): void {
  if (command === 'build') {
    return
  }

  if (env.CI !== undefined) {
    throw new Error(
      `${pluginName}: You should not run the Vite dev server in CI. ` +
        'Run the build command instead.'
    )
  }

  if (env.RAILS_ENV === 'production') {
    throw new Error(
      `${pluginName}: You should not run the Vite dev server in production. ` +
        'Run the build command instead.'
    )
  }
}
