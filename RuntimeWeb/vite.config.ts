import fs from 'node:fs'
import path from 'node:path'
import { defineConfig } from 'vite'

export default defineConfig({
  base: './',
  build: {
    emptyOutDir: true,
    cssCodeSplit: false,
    lib: {
      entry: path.resolve(__dirname, 'src/main.ts'),
      formats: ['iife'],
      name: 'SwiftTerminalRuntime',
      fileName: () => 'runtime.js',
    },
    outDir: path.resolve(
      __dirname,
      '../Sources/SwiftTerminal/Resources/TerminalRuntime',
    ),
    rollupOptions: {
      output: {
        assetFileNames: (assetInfo) => {
          if (assetInfo.names.some((name) => name.endsWith('.css'))) {
            return 'assets/runtime.css'
          }

          return 'assets/[name][extname]'
        },
        entryFileNames: 'assets/runtime.js',
      },
    },
    target: 'es2022',
  },
  plugins: [
    {
      name: 'swiftterminal-runtime-html',
      closeBundle() {
        const outputPath = path.resolve(
          __dirname,
          '../Sources/SwiftTerminal/Resources/TerminalRuntime/index.html',
        )
        const sourceIndexPath = path.resolve(__dirname, 'index.html')
        const sourceHTML = fs.readFileSync(sourceIndexPath, 'utf8')
        const runtimeHTML = sourceHTML.replace(
          /<script\s+type="module"\s+src="\.\/src\/main\.ts"><\/script>/,
          '<link rel="stylesheet" href="./assets/runtime.css" />\n    <script defer src="./assets/runtime.js"></script>',
        )

        fs.writeFileSync(outputPath, runtimeHTML)
      },
    },
  ],
})
