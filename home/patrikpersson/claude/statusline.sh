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
# Usage limits (session / week / per-model week)
# ─────────────────────────────────────────────────────────────────────────────
# Session and weekly windows come with the statusline payload. The per-model
# weekly window (e.g. Fable) does not, so it is read from the same endpoint the
# /usage screen calls, cached on disk and refreshed in the background so the
# statusline never blocks on the network.
USAGE_CACHE="${CLAUDE_USAGE_CACHE:-$HOME/.claude/cache/usage.json}"
USAGE_TTL=300  # seconds

# Linux keeps the OAuth token in ~/.claude/.credentials.json; macOS keeps it
# in the login keychain. Try the file first, then the keychain.
oauth_token() {
    local creds="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json" token=""
    [ -r "$creds" ] && token=$(jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null)
    if [ -z "$token" ] && [ "$(uname -s)" = "Darwin" ]; then
        token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
            | jq -r '.claudeAiOauth.accessToken // empty')
    fi
    printf '%s' "$token"
}

file_mtime() {  # epoch seconds, BSD or GNU stat
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

fmt_epoch() {  # epoch format-string, BSD or GNU date
    date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2" 2>/dev/null
}

refresh_usage_cache() {
    local token
    token=$(oauth_token)
    [ -z "$token" ] && return
    local tmp="${USAGE_CACHE}.tmp.$$"
    if curl -sS -m 10 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" \
        -H "Accept: application/json" -o "$tmp" 2>/dev/null \
        && jq -e '.seven_day' "$tmp" >/dev/null 2>&1; then
        mv -f "$tmp" "$USAGE_CACHE"
    else
        rm -f "$tmp"
    fi
}

cache_age=$USAGE_TTL
if [ -f "$USAGE_CACHE" ]; then
    cache_age=$(( $(date +%s) - $(file_mtime "$USAGE_CACHE") ))
fi
if [ "$cache_age" -ge "$USAGE_TTL" ] && [ -z "$STATUSLINE_NO_FETCH" ]; then
    touch "$USAGE_CACHE" 2>/dev/null   # debounce: only one refresh per TTL
    (refresh_usage_cache &) >/dev/null 2>&1
fi

# Prefer the live payload; fall back to the cache.
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
session_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')
model_label=""; model_pct=""
if [ -s "$USAGE_CACHE" ]; then
    [ -z "$session_pct" ] && session_pct=$(jq -r '.five_hour.utilization // empty' "$USAGE_CACHE")
    [ -z "$week_pct" ] && week_pct=$(jq -r '.seven_day.utilization // empty' "$USAGE_CACHE")
    scoped=$(jq -r '[.limits[]? | select(.kind=="weekly_scoped")][0] | select(. != null) | "\(.scope.model.display_name // "model")\t\(.percent)"' "$USAGE_CACHE")
    if [ -n "$scoped" ]; then
        model_label=$(printf '%s' "$scoped" | cut -f1 | tr '[:upper:]' '[:lower:]')
        model_pct=$(printf '%s' "$scoped" | cut -f2)
    fi
fi

pct_color() {  # green < 50, yellow < 80, red otherwise
    local p=${1%.*}
    if [ "$p" -ge 80 ]; then printf '%s' "$FG_RED"
    elif [ "$p" -ge 50 ]; then printf '%s' "$FG_YELLOW"
    else printf '%s' "$FG_GREEN"; fi
}

fmt_reset() {  # epoch -> "16:00" if today, else "tue 13:00"
    [ -z "$1" ] && return
    local ts=${1%.*}
    if [ "$(fmt_epoch "$ts" +%Y-%m-%d)" = "$(date +%Y-%m-%d)" ]; then
        fmt_epoch "$ts" +%H:%M
    else
        fmt_epoch "$ts" '+%a %H:%M' | tr '[:upper:]' '[:lower:]'
    fi
}

usage_item() {  # label pct [reset-epoch]
    local label=$1 pct=$2 reset=$3 out
    [ -z "$pct" ] && return
    out="${FG_OVERLAY}${label}${NC} $(pct_color "$pct")$(printf '%.0f' "$pct")%${NC}"
    local r; r=$(fmt_reset "$reset")
    [ -n "$r" ] && out="${out} ${FG_SURFACE}↻ ${r}${NC}"
    printf '%s' "$out"
}

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

# Line 3: usage limits - session · week · per-model week
sep="  ${FG_SURFACE}·${NC}  "
line3=""
for item in "$(usage_item session "$session_pct" "$session_reset")" \
            "$(usage_item week "$week_pct" "$week_reset")" \
            "$(usage_item "$model_label" "$model_pct")"; do
    [ -z "$item" ] && continue
    line3="${line3:+${line3}${sep}}${item}"
done
[ -n "$line3" ] && echo -e "$line3"
