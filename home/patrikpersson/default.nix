{ config, pkgs, ... }:

{
  imports = [ ./nvim.nix ./hyprland.nix ./theming.nix ./desktop-shell.nix ./claude.nix ];

  home.username = "patrikpersson";
  home.homeDirectory = "/home/patrikpersson";
  home.stateVersion = "25.11";

  # SSH private key materialised from sops-encrypted secrets/t14.yaml.
  # The user's age key (~/.config/sops/age/keys.txt, derived from this
  # same SSH key via ssh-to-age) is the decryption key. Bootstrap chicken-
  # and-egg: the first key is generated imperatively, then encoded into
  # the YAML — subsequent rotations go via `sops secrets/t14.yaml`.
  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/t14.yaml;
    secrets."ssh/id_ed25519_persson" = {
      path = "${config.home.homeDirectory}/.ssh/id_ed25519";
      mode = "0600";
    };
  };

  programs.git = {
    enable = true;
    settings = {
      user.name = "Patrik Persson";
      user.email = "patrikcpersson@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  # Zen browser (Firefox fork) as the daily driver — replaces the system
  # programs.firefox. setAsDefaultBrowser wires xdg.mimeApps for the
  # http(s)/file schemes and exports $BROWSER, so links from mail and
  # chat clients open here.
  programs.zen-browser = {
    enable = true;
    setAsDefaultBrowser = true;
  };

  programs.ghostty = {
    enable = true;
    enableZshIntegration = true;
    installBatSyntax = true;
    settings = {
      background-opacity = 1;
      window-padding-balance = true;
      theme = "Catppuccin Mocha";
      window-padding-x = 10;
      window-padding-y = 10;
      keybind = [
        # Navigate between splits
        "ctrl+h=goto_split:left"
        "ctrl+j=goto_split:bottom"
        "ctrl+k=goto_split:top"
        "ctrl+l=goto_split:right"
        # Create splits: ctrl+- (horizontal divider), ctrl+| (vertical divider)
        "ctrl+shift+minus=new_split:down"
        "ctrl+shift+backslash=new_split:right"
        "shift+enter=text:\\n"
        "global:ctrl+grave_accent=toggle_quick_terminal"
      ];
      cursor-style = "block";
      cursor-style-blink = false;
      cursor-color = "#ffffff";
      mouse-hide-while-typing = true;
      shell-integration-features = "no-cursor";
      copy-on-select = true;
      window-inherit-working-directory = true;
      font-family = "JetBrainsMono Nerd Font Mono";
      font-thicken = true;
      adjust-cell-height = "25%";
    };
    themes.zenbones-forestbones-dark = {
      background = "#2c343a";
      foreground = "#e7dcc4";
      selection-background = "#615b51";
      selection-foreground = "#e7dcc4";
      cursor-color = "#ebe2cf";
      cursor-text = "#2c343a";
      palette = [
        "0=#2c343a"  "1=#e67c7f"  "2=#a9c181"  "3=#ddbd7f"
        "4=#7fbcb4"  "5=#d69ab7"  "6=#83c193"  "7=#e7dcc4"
        "8=#45525c"  "9=#ed9294"  "10=#b0ce7b" "11=#edc77a"
        "12=#7ac9c0" "13=#e5a7c4" "14=#7dd093" "15=#b2a790"
      ];
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
      # Nix flake refs contain `#`, which EXTENDED_GLOB treats as a glob
      # quantifier — zsh fails with "no matches found" before the tool
      # even runs. `noglob` disables globbing for the command's args.
      nix = "noglob nix";
      "nixos-rebuild" = "noglob nixos-rebuild";
      "nix-shell" = "noglob nix-shell";
      # Trailing space makes zsh expand the next word as an alias too,
      # so `sudo nixos-rebuild …` picks up the noglob alias above.
      sudo = "sudo ";
    };

    # zsh options + keybinds not covered by HM's typed options.
    initContent = ''
      # ── Options ─────────────────────────────────────────────────────
      setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS CORRECT EXTENDED_GLOB NO_BEEP
      setopt HIST_REDUCE_BLANKS INC_APPEND_HISTORY

      # ── Vi-mode timing ──────────────────────────────────────────────
      # 400ms default escape delay feels sluggish in vicmd mode.
      KEYTIMEOUT=1

      # ── Keybinds: prefix-search history with j/k in vicmd ───────────
      bindkey -M vicmd 'k' history-beginning-search-backward
      bindkey -M vicmd 'j' history-beginning-search-forward
      # Arrow keys / Ctrl-p/n: prefix-based history search
      bindkey '^[[A' history-beginning-search-backward
      bindkey '^[[B' history-beginning-search-forward
      bindkey '^P'   history-beginning-search-backward
      bindkey '^N'   history-beginning-search-forward
      # Readline-style line kills
      bindkey '^U' backward-kill-line
      bindkey '^K' kill-line

      # ── Completion cache ────────────────────────────────────────────
      zstyle ':completion:*' use-cache on
      zstyle ':completion:*' cache-path ~/.zsh/cache
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

  programs.atuin = {
    enable = true;
    enableZshIntegration = true;
    # `--disable-up-arrow` keeps the existing prefix-search behaviour on
    # arrow keys (configured in programs.zsh.initContent). Ctrl-R still
    # opens the atuin fuzzy picker.
    flags = [ "--disable-up-arrow" ];
    settings = {
      search_mode = "fuzzy";
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

  # direnv + nix-direnv: per-project devShells activate transparently
  # on `cd`. nix-direnv caches the shell so re-entry is instant and
  # the cached derivation is held as a GC root (which nh clean knows
  # how to reap). hide_env_diff suppresses the noisy "export +FOO -BAR"
  # printout on each cd.
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.global.hide_env_diff = true;
  };

  # Fall back to other completers when carapace lacks a native one.
  home.sessionVariables = {
    CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense";
  };

  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    jq
    nerd-fonts.jetbrains-mono
    sops
    tmux
  ];
}
