import { describe, expect, it } from 'vitest'
import path from 'path'
import { resolveRefreshWatchPaths } from '../src/shared/refresh'

describe('resolveRefreshWatchPaths', () => {
  it('resolves each glob to its static base directory', () => {
    expect(resolveRefreshWatchPaths([
      'app/views/**/*.{erb,slim,haml}',
      'app/{components,helpers}/**/*.rb',
      './config/locales/*.yml',
      '/srv/app/views/**/*.erb',
    ])).toEqual([
      path.resolve('app/views'),
      path.resolve('app'),
      path.resolve('config/locales'),
      '/srv/app/views',
    ])
  })

  it('keeps paths without glob characters', () => {
    expect(resolveRefreshWatchPaths(['config/routes.rb'])).toEqual([path.resolve('config/routes.rb')])
  })

  it('resolves a glob without a static base to the current directory', () => {
    expect(resolveRefreshWatchPaths(['**/*.rb'])).toEqual([process.cwd()])
  })
})
