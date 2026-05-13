# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Simplified Neovim Configuration

This is a minimal, navigation-focused Neovim configuration that emphasizes mastering core Vim capabilities without LSP or AI features.

## Philosophy

- **No LSP**: Learn to navigate using tags, grep, and Vim's built-in features
- **No AI**: Focus on understanding code through reading and exploration
- **Core Vim**: Master the fundamentals that work everywhere
- **Efficient Navigation**: Use modern tools (Telescope, Treesitter) for productivity

## Core Structure

```
~/.config/nvim/
├── init.lua                 # Entry point
├── lua/
│   ├── config/
│   │   ├── lazy.lua        # Plugin manager setup
│   │   ├── options.lua     # Vim options
│   │   └── keymaps.lua     # Navigation-focused keybindings
│   └── plugins/
│       ├── colorscheme.lua # Gruvbox theme
│       ├── telescope.lua   # Fuzzy finding and search
│       ├── treesitter.lua  # Syntax-aware navigation
│       ├── oil.lua         # File explorer as buffers
│       └── flash.lua       # Enhanced character motions
└── .ctags.d/
    └── default.ctags       # Universal ctags configuration
```

## Key Navigation Commands

### File Navigation
- `-` or `<leader>e`: Open Oil file explorer
- `<leader>ff`: Find files (Telescope)
- `<leader>fg`: Live grep in project
- `<leader>fb`: Switch buffers
- `<leader>fo`: Recent files

### Code Navigation
- `gd`: Go to definition (via tags - requires ctags)
- `gr`: Find references (grep word under cursor)
- `*`/`#`: Search word under cursor forward/backward
- `gD`: Go to global definition (Vim built-in)
- `gf`: Go to file under cursor

### Treesitter Navigation
- `]m`/`[m`: Next/previous function
- `]]`/`[[`: Next/previous class
- `]o`/`[o`: Next/previous loop
- `]s`/`[s`: Next/previous statement
- `af`/`if`: Select around/inside function
- `ac`/`ic`: Select around/inside class

### Jump Navigation
- `Ctrl-O`: Jump back in history
- `Ctrl-I`: Jump forward in history
- `<leader>jo`/`<leader>ji`: Alternative jump bindings
- `''`: Jump to last position
- `g;`/`g,`: Navigate change list

### Enhanced Motions (Flash)
- `s`: Flash jump to character
- `S`: Flash Treesitter jump
- `f`/`F`/`t`/`T`: Enhanced with labels

### Quickfix & Location Lists
- `[q`/`]q`: Previous/next quickfix item
- `<leader>co`/`<leader>cc`: Open/close quickfix
- `[l`/`]l`: Previous/next location item
- `<leader>lo`/`<leader>lc`: Open/close location list

## Setting Up Tags

For go-to-definition without LSP, generate tags for your project:

```bash
# Generate tags for current directory
ctags -R .

# Or use the configured ctags with our settings
ctags --options=$HOME/.config/nvim/.ctags.d/default.ctags

# Auto-generate on save (add to init.lua if desired)
vim.cmd([[autocmd BufWritePost * silent! !ctags -R .]])
```

## Refactoring Workflows

### Project-Wide Search & Replace
1. `<leader>fg` - Live grep for pattern
2. `Ctrl-q` - Send results to quickfix
3. `:cdo s/old/new/g` - Replace in all quickfix files
4. `:wa` - Save all changes

### Word Under Cursor Replace
- `<leader>rw` - Replace word under cursor (whole file)
- Visual select + `<leader>r` - Replace in selection

### Macro-Based Refactoring
1. `qa` - Start recording macro to register 'a'
2. Perform the refactoring steps
3. `q` - Stop recording
4. `Q` - Replay macro (mapped to @q)
5. Visual select + `Q` - Apply macro to selection

## Essential Vim Commands to Master

### Text Objects
- `ci"` - Change inside quotes
- `da(` - Delete around parentheses
- `vi{` - Visual select inside braces
- `yap` - Yank a paragraph

### Marks
- `ma` - Set mark 'a'
- `'a` - Jump to mark 'a' line
- `` `a`` - Jump to mark 'a' position
- `<leader>ml` - List all marks
- `<leader>md` - Delete all marks

### Registers
- `"ay` - Yank to register 'a'
- `"ap` - Paste from register 'a'
- `<leader>fr` - View all registers (Telescope)

### Window Management
- `Ctrl-w v` - Vertical split
- `Ctrl-w s` - Horizontal split
- `Ctrl-h/j/k/l` - Navigate windows
- `<leader>sv`/`sh`/`se`/`sx` - Split management

## Tips for Mastery

1. **Use relative line numbers**: Makes jump motions (`5j`, `10k`) efficient
2. **Learn text objects**: They're composable and powerful
3. **Master the dot command**: `.` repeats last change
4. **Use marks liberally**: They're free navigation points
5. **Embrace the quickfix**: Your refactoring command center
6. **Tags are powerful**: Keep them updated for definition jumping
7. **Grep is your friend**: Learn ripgrep patterns for efficient searching

## Common Development Tasks

### Generate Tags
```bash
ctags -R .                   # Basic tags generation
ctags -R --exclude=node_modules --exclude=.git .  # With exclusions
```

### Search Patterns
```vim
:vimgrep /pattern/g **/*.js  " Search in all JS files
:grep -r "TODO" .            " Find all TODOs
:Telescope live_grep         " Interactive search
```

### Navigation Practice
- Try navigating without mouse for a week
- Use `Ctrl-O/I` instead of clicking back
- Use marks for frequently visited spots
- Use `gd` for definitions (requires tags)