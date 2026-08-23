{ pkgs, inputs, ... }:

# Claude Code configuration, managed declaratively via home-manager's
# `programs.claude-code` module.
#
# `settings.json` is generated into the read-only nix store and symlinked
# into ~/.claude/ — so the in-app `/config` UI can no longer persist
# changes. Edit this file and rebuild instead. (The genuinely churny
# per-machine state — OAuth, onboarding flags, caches — lives in the
# separate ~/.claude.json, which is left mutable and untouched.)
#
# The `settings` attrset is split into a shared base and a t14-specific
# section. When the dotfiles repo becomes a flake input (roadmap Step 5),
# the base lifts out for cross-machine reuse and only the host section
# stays here.

{
  programs.claude-code = {
    enable = true;

    # claude-code itself is a system package (hosts/<host>/default.nix);
    # this module manages config files only, not the binary.
    package = null;

    # `memory.source` is set per-host (default.nix, server.nix) — each
    # host concatenates its own `CLAUDE.<host>.md` (Environment section)
    # with the shared `CLAUDE.common.md` (universal rules).

    settings = {
      # ── Shared base (identical on every machine) ──────────────────
      cleanupPeriodDays = 36500;
      includeCoAuthoredBy = false;
      alwaysThinkingEnabled = true;
      editorMode = "vim";
      effortLevel = "high";
      # Default model for new sessions. `/model` can switch per-session,
      # but its "save as default" writes to settings.json, which is a
      # read-only nix-store symlink here — so the default lives in Nix.
      model = "claude-fable-5";
      skipDangerousModePermissionPrompt = true;

      env = {
        CLAUDE_CODE_ENABLE_TELEMETRY = "1";
        MAX_THINKING_TOKENS = "31999";
      };

      enabledPlugins = {
        "rust-analyzer-lsp@claude-plugins-official" = true;
        "pyright-lsp@claude-plugins-official" = true;
        "clangd-lsp@claude-plugins-official" = true;
      };

      statusLine = {
        type = "command";
        command = "~/.claude/statusline.sh";
        padding = 0;
      };

      permissions = {
        defaultMode = "acceptEdits";
        deny = [ ];
        allow = [
          "Read(**)"
          "Grep(**)"
          "Glob(**)"
          "WebSearch"
          "Bash(ls:*)"
          "Bash(cat:*)"
          "Bash(grep:*)"
          "Bash(rg:*)"
          "Bash(cp:*)"
          "Bash(find:*)"
          "Bash(pwd)"
          "Bash(echo:*)"
          "Bash(whoami)"
          "Bash(source:*)"
          "Bash(sed:*)"
          "Bash(head:*)"
          "Bash(tail:*)"
          "Bash(mkdir:*)"
          "Bash(mv:*)"
          "Bash(touch:*)"
          "Bash(cd:*)"
          "Bash(tree:*)"
          "Bash(type:*)"
          "Bash(which:*)"
          "Bash(git:*)"
          "Bash(bun:*)"
          "Bash(npm:*)"
          "Bash(pnpm:*)"
          "Bash(yarn:*)"
          "Bash(python:*)"
          "Bash(pytest:*)"
          "Bash(uv:*)"
          "Bash(mypy:*)"
          "Bash(ruff:*)"
          "Bash(black:*)"
          "Bash(flake8:*)"
          "Bash(eslint:*)"
          "Bash(tsc:*)"
          "WebFetch(domain:github.com)"
          "WebFetch(domain:raw.githubusercontent.com)"
          "WebFetch(domain:docs.github.com)"
          "WebFetch(domain:api.github.com)"
          "WebFetch(domain:npmjs.com)"
          "WebFetch(domain:pypi.org)"
          "WebFetch(domain:docs.python.org)"
          "WebFetch(domain:developer.mozilla.org)"
          "WebFetch(domain:stackoverflow.com)"
          "WebFetch(domain:docs.anthropic.com)"
          "WebFetch(domain:code.anthropic.com)"
        ];
        ask = [
          "Bash(git push:*)"
          "Bash(git pull:*)"
          "Bash(git fetch:*)"
          "Bash(git reset:*)"
          "Bash(git clean:*)"
          "Bash(git checkout .:*)"
          "Bash(git rebase:*)"
          "Bash(git stash:*)"
          "Bash(npm publish:*)"
          "Bash(bun publish:*)"
          "Bash(uv publish:*)"
        ];
      };

      # Desktop notifications via notify-send (libnotify). On a headless
      # box without a notification daemon, the command is a no-op rather
      # than an error, so this is safe to share across hosts.
      hooks.Notification = [
        {
          matcher = "";
          hooks = [
            {
              type = "command";
              command = "notify-send --app-name='Claude Code' \"$CLAUDE_NOTIFICATION\"";
            }
          ];
        }
      ];
      # Fullscreen TUI — preferred regardless of host.
      tui = "fullscreen";
    };
  };

  # statusline script — must stay a real file (referenced by
  # settings.statusLine.command above); the module has no option for it.
  home.file.".claude/statusline.sh" = {
    source = ./claude/statusline.sh;
    executable = true;
  };

  # worklog — the `worklog` CLI (DuckDB-indexed query over Claude Code
  # transcripts) plus its driving skill, from the papershop marketplace.
  # Native nix consumption: a binary on PATH and the skill file, no
  # plugin/marketplace/hook. The script reads WORKLOG_DB /
  # WORKLOG_DUCKDB_EXTENSION_DIR, both set by the flake's wrapper to a
  # writable XDG cache.
  home.packages = [ inputs.papershop.packages.${pkgs.system}.worklog ];
  home.file.".claude/skills/worklog/SKILL.md".source = "${inputs.papershop}/worklog/skills/worklog/SKILL.md";

  # orchestrate — the meta-workflow skill (gate a task, scope it, fire a
  # dynamic workflow) plus its invocation templates. Symlink the whole skill
  # directory so templates/ resolves next to SKILL.md.
  home.file.".claude/skills/orchestrate".source = "${inputs.papershop}/orchestrate/skills/orchestrate";

  # prose — style-only rewrite + teaching review, grounded in reference.md.
  # Symlink the whole skill dir so reference.md resolves next to SKILL.md.
  home.file.".claude/skills/prose".source = "${inputs.papershop}/prose/skills/prose";

  # performance-engineering — perf analysis/optimization skill plus its
  # modules/. Symlink the whole skill dir so modules/ resolves next to SKILL.md.
  home.file.".claude/skills/performance-engineering".source = "${inputs.papershop}/performance-engineering/skills/performance-engineering";
}
