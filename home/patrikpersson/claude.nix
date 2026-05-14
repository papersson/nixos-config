{ ... }:

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

    # claude-code itself is a system package (hosts/t14/default.nix);
    # this module manages config files only, not the binary.
    package = null;

    # CLAUDE.md global instructions — typed equivalent of the old
    # `home.file.".claude/CLAUDE.md"`.
    memory.source = ./claude/CLAUDE.md;

    settings = {
      # ── Shared base (identical on every machine) ──────────────────
      cleanupPeriodDays = 36500;
      includeCoAuthoredBy = false;
      alwaysThinkingEnabled = true;
      editorMode = "vim";
      effortLevel = "high";
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
        defaultMode = "default";
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

      # ── t14-specific ──────────────────────────────────────────────
      # Linux desktop notifications via mako (macOS uses terminal-notifier).
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
      # Fullscreen TUI suits the tiling-WM workflow on this machine.
      tui = "fullscreen";
    };
  };

  # statusline script — must stay a real file (referenced by
  # settings.statusLine.command above); the module has no option for it.
  home.file.".claude/statusline.sh" = {
    source = ./claude/statusline.sh;
    executable = true;
  };
}
