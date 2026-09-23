import {copyFileSync} from 'node:fs'
copyFileSync(new URL('../dist/index.html',import.meta.url),new URL('../dist/404.html',import.meta.url))
