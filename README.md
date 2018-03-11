<h1 align="center">
  .meta
</h1>

<div align="center">

  Some files to use for Node based projects
</div>

## Features

- Linting:
  - Includes full Eslint configuration
    - Uses my own preferences overlaid on top of the `standard` code style convention
  - Lints commit messages with commitlintrc
- Has git hooks support with [Husky](https://github.com/typicode/husky)
- Has Babel config for Node 8 and above
  - Supports async functions
  - Only transpiles if the current environment needs it
- Configures supported code editors with [editorconfig](http://editorconfig.org/):
  - 2 spaces for indentation
  - Forces empty newline before EOF
  - Removes trailing whitespaces
    - Except in Markdown files
  - Forces Unix style line endings
  - Sets utf-8 file encoding
- Has gitignore support for...
  - Linux
    - Dolphin (and any file browser that uses .directory)
  - Windows
  - MacOS
  - Docker
  - NodeJS
  - Vim
  - Sublime Text
  - Kate
  - Dropbox
