{ config, pkgs, lib, ... }:

# Minimal home-manager entry point for headless/server hosts.
# Imports only CLI tooling — no Hyprland, theming, desktop-shell, or browser.
{
  imports = [ ./nvim.nix ./claude.nix ./codex.nix ];

  home.username = "patrikpersson";
  home.homeDirectory = "/home/patrikpersson";
  home.stateVersion = "25.11";

  # Rex personal server, reached from the Mac as `rex -S z840`
  # (ssh://server). Runs as a systemd user service; lingering in
  # hosts/z840 keeps it, and its sessions, alive while logged out.
  services.rex.enable = true;

  # Claude Code Remote Control server, launched from ~/Code (sessions can
  # work in any folder; ~ itself cannot hold a saved trust): registers z840 as an
  # environment on the claude.ai account, so project threads and
  # claude.ai/code sessions run here without the Mac. Lingering keeps it up
  # while logged out; Restart=always brings it back after the ~10 min
  # network-loss exit. claude comes from the system profile, so a
  # claude-bump does not restart it (running sessions survive); it picks up
  # the new version on the next restart or reboot.
  # One-time: the trust prompt for ~/Code was answered interactively.
  systemd.user.services.claude-remote-control = {
    Unit = {
      Description = "Claude Code Remote Control (~/Code)";
      After = [ "network-online.target" ];
      StartLimitIntervalSec = 0;
    };
    Service = {
      WorkingDirectory = "%h/Code";
      ExecStart = "/run/current-system/sw/bin/claude remote-control --name z840";
      Environment = [
        "PATH=/run/wrappers/bin:/etc/profiles/per-user/patrikpersson/bin:/run/current-system/sw/bin"
      ];
      Restart = "always";
      RestartSec = "15s";
      TimeoutStopSec = "30s";
      # The TUI redraws its status line every second; keep it out of the journal.
      StandardOutput = "null";
    };
    Install.WantedBy = [ "default.target" ];
  };

  # Nightly bump of Claude Code, papershop skills, Codex and Atuin: one
  # rebuild, one local commit, reverted on failure. See nightly-bump.sh for
  # what it leaves out (Rex) and why. Run now: `systemctl --user start
  # nightly-bump`; log: `journalctl --user -u nightly-bump`.
  systemd.user.services.nightly-bump = {
    Unit = {
      Description = "Bump Claude Code, papershop, Codex and Atuin, then rebuild";
      After = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe (pkgs.writeShellApplication {
        name = "nightly-bump";
        runtimeInputs = with pkgs; [ git jq curl gnused gnugrep coreutils ];
        text = builtins.readFile ./nightly-bump.sh;
      });
      # nix, sudo and nixos-rebuild come from the system, as in the
      # interactive *-bump functions.
      Environment = [
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin"
      ];
    };
  };
  systemd.user.timers.nightly-bump = {
    Unit.Description = "Nightly agent-tool bump";
    Timer = {
      OnCalendar = "*-*-* 04:30";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # Lets the Rex module add its ssh guard to ~/.ssh/config, so ssh from a
  # Rex pane sends TERM=xterm-256color to hosts that lack xterm-rex.
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
  };

  # Concatenate the z840 Environment section with the shared common rules,
  # then hand the resulting file to programs.claude-code.memory.source.
  programs.claude-code.memory.source = pkgs.writeText "CLAUDE.md" (
    builtins.readFile ./claude/CLAUDE.z840.md
    + "\n"
    + builtins.readFile ./claude/CLAUDE.common.md
  );

  # z840 sessions start in bypass-permissions mode (no tool prompts).
  # Overrides the shared "acceptEdits" default in claude.nix; t14 keeps that.
  # Root-level damage is still bounded by the scoped sudo rules in
  # hosts/z840/default.nix.
  programs.claude-code.settings.permissions.defaultMode = lib.mkForce "bypassPermissions";

  # Long autonomous agent runs (e.g. the click-save film polish passes) are
  # launched by Claude as agy inside a rex session with approvals off. Sessions
  # that run in auto mode instead of bypass need these explicit rules, or the
  # auto-mode classifier refuses the launch. Merged with the shared allow list.
  programs.claude-code.settings.permissions.allow = [
    "Bash(rex new:*)"
    "Bash(agy --model:*)"
  ];

  # movie-server — z840-only skill: add movies/shows and babysit downloads via
  # the *arr APIs (uses media-queue / media-watch / arr-apikey from
  # hosts/z840). Lives here rather than papershop because it's host-specific.
  home.file.".claude/skills/movie-server".source = ./claude/skills/movie-server;

  programs.git = {
    enable = true;
    settings = {
      user.name = "Patrik Persson";
      user.email = "patrikcpersson@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    defaultKeymap = "viins";

    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      ignoreSpace = true;
      share = true;
      extended = false;
    };

    shellAliases = {
      ls = "eza";
      ll = "eza -lah";
      la = "eza -a";
      ".." = "cd ..";
      "..." = "cd ../..";
      md = "mkdir -p";
      rd = "rmdir";
      g = "git";
      reload = "source ~/.zshrc";
      rm = "rm -i";
      cp = "cp -i";
      mv = "mv -i";
      nix = "noglob nix";
      "nixos-rebuild" = "noglob nixos-rebuild";
      "nix-shell" = "noglob nix-shell";
      sudo = "sudo ";
    };

    initContent = ''
      setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS CORRECT EXTENDED_GLOB NO_BEEP
      setopt HIST_REDUCE_BLANKS INC_APPEND_HISTORY

      KEYTIMEOUT=1

      bindkey -M vicmd 'k' history-beginning-search-backward
      bindkey -M vicmd 'j' history-beginning-search-forward
      bindkey '^[[A' history-beginning-search-backward
      bindkey '^[[B' history-beginning-search-forward
      bindkey '^P'   history-beginning-search-backward
      bindkey '^N'   history-beginning-search-forward
      bindkey '^U' backward-kill-line
      bindkey '^K' kill-line

      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path ~/.zsh/cache

      # ── claude-bump: pull the newest Claude Code ────────────────────
      # Re-locks the nix-claude-code input (auto-bumps hourly upstream to
      # Anthropic's latest release), rebuilds, then commits the lock only
      # if the build succeeded — so a broken bump never lands in git.
      # Subshell keeps the flake `cd` from leaking into the interactive cwd.
      claude-bump() {
        ( cd "$HOME/nixos-config" && nix flake update nix-claude-code ) || return 1
        nh os switch || return 1
        git -C "$HOME/nixos-config" commit -m "claude: bump nix-claude-code to latest" flake.lock
      }

      # ── papershop-bump: pull the newest papershop skills ────────────
      # Same shape as claude-bump. Wired skills (papershopSkills in
      # claude.nix) follow this one lock entry; a skill upstream dropped
      # fails the build, so nothing is committed.
      papershop-bump() {
        ( cd "$HOME/nixos-config" && nix flake update papershop ) || return 1
        sudo -n /run/current-system/sw/bin/nixos-rebuild switch --flake "$HOME/nixos-config#z840" || return 1
        git -C "$HOME/nixos-config" commit -m "claude: bump papershop to latest" flake.lock
      }

      # ── codex-bump: pull the newest Codex CLI ───────────────────────
      # Looks up the latest GitHub release, prefetches the x86_64 musl
      # bundle, rewrites version + hash in pkgs/codex.nix, rebuilds, and
      # commits only if the build succeeded.
      codex-bump() {
        local repo="$HOME/nixos-config" f="$HOME/nixos-config/pkgs/codex.nix" tag ver hash
        tag=$(curl -fsSL https://api.github.com/repos/openai/codex/releases/latest | jq -r .tag_name) || return 1
        ver=''${tag#rust-v}
        if grep -q "version = \"$ver\"" "$f"; then echo "codex already at $ver"; return 0; fi
        hash=$(nix store prefetch-file --json \
          "https://github.com/openai/codex/releases/download/$tag/codex-package-x86_64-unknown-linux-musl.tar.zst" \
          | jq -r .hash) || return 1
        sed -i -e "s|version = \".*\";|version = \"$ver\";|" \
               -e "s|hash = \"sha256-.*\";|hash = \"$hash\";|" "$f"
        nh os switch || return 1
        git -C "$repo" commit -m "codex: bump to $ver" pkgs/codex.nix
      }

      # ── atuin-bump: pull the newest Atuin ───────────────────────────
      # Same shape as codex-bump, for pkgs/atuin.nix's static musl build.
      atuin-bump() {
        local repo="$HOME/nixos-config" f="$HOME/nixos-config/pkgs/atuin.nix" tag ver hash
        tag=$(curl -fsSL https://api.github.com/repos/atuinsh/atuin/releases/latest | jq -r .tag_name) || return 1
        ver=''${tag#v}
        if grep -q "version = \"$ver\"" "$f"; then echo "atuin already at $ver"; return 0; fi
        hash=$(nix store prefetch-file --json \
          "https://github.com/atuinsh/atuin/releases/download/$tag/atuin-x86_64-unknown-linux-musl.tar.gz" \
          | jq -r .hash) || return 1
        sed -i -e "s|version = \".*\";|version = \"$ver\";|" \
               -e "s|hash = \"sha256-.*\";|hash = \"$hash\";|" "$f"
        nh os switch || return 1
        git -C "$repo" commit -m "atuin: bump to $ver" pkgs/atuin.nix
      }
    '';
  };

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = builtins.fromTOML (builtins.readFile ./starship.toml);
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # Shell history plus every agent's threads (Claude Code, Codex), searchable
  # with `atuin resume` and over MCP. The daemon captures threads by reading
  # the agents' transcript files; home-manager runs it as a socket-activated
  # user service that is also wanted by default.target, so with lingering it
  # is up from boot. The MCP entry lives in the mutable ~/.claude.json
  # (`claude mcp add -s user atuin -- atuin mcp`): programs.claude-code can
  # only add MCP servers by wrapping its package, which is null here.
  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    flags = [ "--disable-up-arrow" ];
    daemon.enable = true;
    settings = {
      # The daemon's in-memory index; `atuin setup --daemon` sets the same.
      search_mode = "daemon-fuzzy";
      threads.enabled = true;
      # The systemd socket is %t/atuin.sock, and atuin finds it through
      # $XDG_RUNTIME_DIR, which Tailscale SSH and Rex panes leave unset; without
      # this, `atuin resume` and `atuin mcp` there report "Daemon is not
      # running". 1000 is the auto-assigned uid of patrikpersson.
      daemon.socket_path = "/run/user/1000/atuin.sock";
      filter_mode = "directory";
      filter_mode_shell_up_key_binding = "global";
      keymap_mode = "vim-insert";
      keymap_cursor = {
        vim_insert = "blink-bar";
        vim_normal = "steady-block";
      };
      style = "compact";
      inline_height = 40;
      enter_accept = true;
      secrets_filter = true;
      history_filter = [
        "^export .*="
        "^source "
      ];
    };
  };

  programs.carapace = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.global.hide_env_diff = true;
  };

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.btop.enable = true;

  programs.tmux.enable = true;

  home.sessionVariables = {
    CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense";
    # agent-browser's `install` downloads a Chrome-for-Testing binary that
    # won't run on NixOS (no FHS dynamic linker); point it at nix chromium.
    AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.chromium}/bin/chromium";
  };

  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    jq
    nerd-fonts.jetbrains-mono
    sops
    ssh-to-age
    unstable.agent-browser
    chromium
    antigravity-cli
    # Media tooling for Studio film work run by agents outside Studio's own env
    # (tools/*.py, make-clips.sh): python with numpy + Pillow, ffmpeg, sox.
    (python3.withPackages (ps: [ ps.numpy ps.pillow ]))
    ffmpeg
    sox
  ];
}
