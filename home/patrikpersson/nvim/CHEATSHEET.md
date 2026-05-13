# Neovim Navigation Cheat Sheet

## 🎯 MUST MEMORIZE (Daily Use)

### Core Navigation
```
JUMPING
Ctrl-O          Jump back (previous location)
Ctrl-I          Jump forward (next location)
''              Jump to last position
gd              Go to definition (local/tags)
gf              Go to file under cursor
*               Search word forward
#               Search word backward

MOVING FAST
s               Flash jump (then type chars)
S               Flash Treesitter jump
]m / [m         Next/prev function
]] / [[         Next/prev class
}  / {          Next/prev paragraph
%               Jump to matching bracket
```

### File & Search
```
FINDING STUFF
<leader>fg      Live grep (search content)
<leader>ff      Find files
<leader>fb      Find buffers
gr              Grep word under cursor
-               Open file explorer (Oil)

QUICKFIX (After Search)
Ctrl-q          Send search results to quickfix
:cdo s/x/y/g    Replace in all quickfix files
[q / ]q         Navigate quickfix items
```

### Text Manipulation
```
CHANGE/DELETE/YANK + MOTION
ciw             Change inside word
ci"             Change inside quotes
da(             Delete around parentheses
yap             Yank a paragraph
vaf             Visual select function
daf             Delete a function

VISUAL MODE
v               Character selection
V               Line selection
Ctrl-v          Block selection
gv              Reselect last selection
```

## 💪 PRACTICE DAILY (Build Muscle Memory)

### Window Management
```
Ctrl-w v        Vertical split
Ctrl-w s        Horizontal split
Ctrl-h/j/k/l    Navigate windows
Ctrl-w q        Close window
```

### Marks & Registers
```
ma              Set mark 'a'
'a              Jump to mark 'a' (line)
`a              Jump to mark 'a' (exact)
"ay             Yank to register 'a'
"ap             Paste from register 'a'
```

### Macros
```
qa              Record macro to 'a'
q               Stop recording
@a              Play macro 'a'
Q               Play macro 'q' (custom mapping)
```

## 🔄 REFACTORING PATTERNS

### Pattern 1: Project-Wide Replace
```
1. <leader>fg              Search for pattern
2. Ctrl-q                  Send to quickfix
3. :cdo s/old/new/gc      Replace with confirm
4. :wa                     Save all
```

### Pattern 2: Quick Local Replace
```
1. *                       Search word
2. cgn                     Change next occurrence
3. .                       Repeat change (dot command)
4. .                       Keep pressing to replace more
```

### Pattern 3: Visual Block Edit
```
1. Ctrl-v                  Block select
2. Select column
3. I                       Insert at beginning
4. Type text
5. Esc                     Apply to all lines
```

## 🎮 MOVEMENT DRILLS

### Drill 1: Jump History (5 min/day)
```
1. Jump to random files/functions
2. Use ONLY Ctrl-O to go back
3. Use Ctrl-I to go forward
4. Never use mouse or :e
```

### Drill 2: Text Objects (5 min/day)
```
Practice these combos:
- ci" → di" → yi"        (quotes)
- ciw → diw → yiw        (words)
- ci( → di( → yi(        (parens)
- caf → daf → yaf        (functions)
```

### Drill 3: Search & Jump (5 min/day)
```
1. Use * to search word
2. Use n/N to navigate
3. Use cgn to change
4. Use . to repeat
```

## 🚀 SPEED COMBOS

```
dt<char>        Delete to character
ct<char>        Change to character
vt<char>        Select to character
f<char>         Jump to character
zz              Center screen
gg              Go to top
G               Go to bottom
0               Start of line
$               End of line
^               First non-blank char
```

## 📍 TELESCOPE SHORTCUTS

```
In Telescope:
Ctrl-j/k        Navigate results
Ctrl-q          Send to quickfix
Ctrl-v          Open in vertical split
Ctrl-x          Open in horizontal split
Ctrl-t          Open in new tab
Esc             Close
```

## 🎯 ONE-WEEK CHALLENGE

**Day 1-2**: Master Ctrl-O/I jumping
**Day 3-4**: Master text objects (ciw, ci", daf)
**Day 5-6**: Master search & replace patterns
**Day 7**: Combine all - navigate and refactor without mouse

## 💡 GOLDEN RULES

1. **NO MOUSE** - Hands stay on keyboard
2. **NO ARROWS** - Use hjkl
3. **NO REPEATING** - Use counts (5j instead of jjjjj)
4. **THINK OBJECTS** - Don't delete char by char
5. **USE MARKS** - Set marks in files you'll revisit
6. **EMBRACE QUICKFIX** - Your refactoring command center

---
*Print this out. Review daily. Practice until automatic.*