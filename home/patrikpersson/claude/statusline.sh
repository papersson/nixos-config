#!/usr/bin/env bash

# Claude Code statusline - minimal style

input=$(cat)

# ─────────────────────────────────────────────────────────────────────────────
# True Color
# ─────────────────────────────────────────────────────────────────────────────
tc_fg() { printf '\033[38;2;%d;%d;%dm' "$1" "$2" "$3"; }

# Claude brand coral/orange
FG_CLAUDE=$(tc_fg 217 119 87)

# Catppuccin Mocha
FG_GREEN=$(tc_fg 166 227 161)
FG_YELLOW=$(tc_fg 249 226 175)
FG_RED=$(tc_fg 243 139 168)
FG_TEXT=$(tc_fg 205 214 244)
FG_SUBTEXT=$(tc_fg 166 173 200)
FG_OVERLAY=$(tc_fg 108 112 134)
FG_SURFACE=$(tc_fg 69 71 90)

NC='\033[0m'

# ─────────────────────────────────────────────────────────────────────────────
# Extract JSON data
# ─────────────────────────────────────────────────────────────────────────────
model_name=$(echo "$input" | jq -r '.model.display_name // "Claude"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // "~"')

# Context window
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
current_usage=$(echo "$input" | jq '.context_window.current_usage')

if [ "$current_usage" != "null" ]; then
    current_tokens=$(echo "$current_usage" | jq '(.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0)')
    context_percent=$((current_tokens * 100 / context_size))
else
    current_tokens=0
    context_percent=0
fi

tokens_display=$(awk "BEGIN {printf \"%.0fk\", $current_tokens/1000}")

# Cost
session_cost_raw=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
cost_display=""
if [ -n "$session_cost_raw" ] && [ "$session_cost_raw" != "null" ]; then
    cost_display=$(printf "\$%.2f" "$session_cost_raw")
fi

# ─────────────────────────────────────────────────────────────────────────────
# Context Progress Bar
# ─────────────────────────────────────────────────────────────────────────────
bar_width=20
filled=$((context_percent * bar_width / 100))
empty=$((bar_width - filled))

# Build bar (muted subtext color)
bar="${FG_SUBTEXT}"
for ((i=0; i<filled; i++)); do bar+="█"; done
bar+="${NC}"
for ((i=0; i<empty; i++)); do bar+="${FG_SURFACE}░${NC}"; done

# ─────────────────────────────────────────────────────────────────────────────
# Git Branch
# ─────────────────────────────────────────────────────────────────────────────
ICON_GIT=$'\xee\x82\xa0'  # Nerd Font git branch icon (U+E0A0)

cd "$current_dir" 2>/dev/null || cd /

branch=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch="detached"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Output
# ─────────────────────────────────────────────────────────────────────────────

# Line 1: Model in /path on branch
display_dir="${current_dir/#$HOME/~}"
line1="${FG_CLAUDE}${model_name}${NC} ${FG_OVERLAY}in${NC} ${FG_TEXT}${display_dir}${NC}"
if [ -n "$branch" ]; then
    line1="${line1} ${FG_OVERLAY}on${NC} ${FG_SUBTEXT}${ICON_GIT} ${branch}${NC}"
fi
echo -e "$line1"

# Line 2: progress bar + percent + tokens + cost
line2="${bar} ${FG_SUBTEXT}${context_percent}%${NC} ${FG_OVERLAY}${tokens_display}${NC}"
if [ -n "$cost_display" ]; then
    line2="${line2}  ${FG_OVERLAY}${cost_display}${NC}"
fi
echo -e "$line2"
