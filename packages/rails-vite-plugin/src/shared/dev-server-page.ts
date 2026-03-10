import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

export function readDevServerIndexHtml(): string {
  return fs.readFileSync(
    path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', 'dev-server-index.html'),
    'utf-8'
  )
}
