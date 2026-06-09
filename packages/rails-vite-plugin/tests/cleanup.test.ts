import { afterEach, describe, expect, it, vi } from 'vitest'
import fs from 'fs'
import { removeOwnedFile } from '../src/shared/cleanup'

vi.mock('fs', async () => {
  const actual = await vi.importActual<typeof import('fs')>('fs')
  return {
    default: {
      ...actual,
      readFileSync: vi.fn(),
      rmSync: vi.fn(),
    },
  }
})

describe('cleanup helpers', () => {
  afterEach(() => {
    vi.mocked(fs.readFileSync).mockReset()
    vi.mocked(fs.rmSync).mockReset()
  })

  it('removes a file owned by the current process', () => {
    vi.mocked(fs.readFileSync).mockReturnValue(JSON.stringify({ pid: 123 }))

    removeOwnedFile('tmp/rails-vite.json', 123)

    expect(fs.rmSync).toHaveBeenCalledWith('tmp/rails-vite.json', { force: true })
  })

  it('keeps a file owned by another process', () => {
    vi.mocked(fs.readFileSync).mockReturnValue(JSON.stringify({ pid: 456 }))

    removeOwnedFile('tmp/rails-vite.json', 123)

    expect(fs.rmSync).not.toHaveBeenCalled()
  })

  it('keeps files without readable ownership metadata', () => {
    vi.mocked(fs.readFileSync).mockReturnValue('{')

    removeOwnedFile('tmp/rails-vite.json', 123)

    expect(fs.rmSync).not.toHaveBeenCalled()
  })
})
