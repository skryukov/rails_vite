import { afterEach, describe, expect, it } from 'vitest'
import { createServer, resolveConfig, type InlineConfig, type Plugin } from 'vite'
import rails from '../src'
import jsbundling from '../src/jsbundling'

function viteConfig(plugin: Plugin): InlineConfig {
  return {
    configFile: false,
    logLevel: 'silent',
    plugins: [plugin],
  }
}

describe('environment guards', () => {
  afterEach(() => {
    delete process.env.CI
    delete process.env.RAILS_ENV
  })

  it('allows rails() config resolution in CI', async () => {
    process.env.CI = 'true'

    await expect(
      resolveConfig(viteConfig(rails({ input: 'application.js' })), 'serve', 'development'),
    ).resolves.toBeDefined()
  })

  it('rejects rails() dev server startup in CI', async () => {
    process.env.CI = 'true'

    await expect(
      createServer(viteConfig(rails({ input: 'application.js' }))),
    ).rejects.toThrowError('should not run the Vite dev server in CI')
  })

  it('allows jsbundling() config resolution in CI', async () => {
    process.env.CI = 'true'

    await expect(
      resolveConfig(viteConfig(jsbundling({ input: 'application.js' })), 'serve', 'development'),
    ).resolves.toBeDefined()
  })

  it('rejects jsbundling() dev server startup in CI', async () => {
    process.env.CI = 'true'

    await expect(
      createServer(viteConfig(jsbundling({ input: 'application.js' }))),
    ).rejects.toThrowError('should not run the Vite dev server in CI')
  })
})
