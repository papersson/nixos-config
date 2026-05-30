{ config, pkgs, lib, ... }:

let
  # Pull a hex colour from the matugen palette (same accessor pattern as
  # desktop-shell.nix). Used to build the Ghostty theme below so the
  # terminal tracks the wallpaper instead of sitting on a fixed Catppuccin.
  c = role: config.programs.matugen.theme.colors.${role}.default.color;
in
{
  imports = [ ./nvim.nix ./hyprland.nix ./theming.nix ./desktop-shell.nix ./claude.nix ];

  home.username = "patrikpersson";
  home.homeDirectory = "/home/patrikpersson";
  home.stateVersion = "25.11";

  # Concatenate the t14 Environment section with the shared common rules,
  # then hand the resulting file to programs.claude-code.memory.source.
  programs.claude-code.memory.source = pkgs.writeText "CLAUDE.md" (
    builtins.readFile ./claude/CLAUDE.t14.md
    + "\n"
    + builtins.readFile ./claude/CLAUDE.common.md
  );

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

  programs.ssh = {
    enable = true;
    matchBlocks.server = {
      hostname = "192.168.1.10";
      user = "patrikpersson";
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
      # Built theme below — driven by the matugen palette so the terminal
      # re-tints with the wallpaper on rebuild.
      theme = "matugen";
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
        # Close the focused split. Linux has no default close_surface bind;
        # falls through to closing the tab/window when it's the last surface.
        "ctrl+shift+w=close_surface"
        "shift+enter=text:\\n"
        "global:ctrl+grave_accent=toggle_quick_terminal"
      ];
      cursor-style = "block";
      cursor-style-blink = false;
      mouse-hide-while-typing = true;
      # G502 wheel emits high-res sub-events per detent; default 3.0
      # multiplies into ~20 lines/notch. 1.0 brings it back to sane.
      mouse-scroll-multiplier = 1.0;
      shell-integration-features = "no-cursor";
      copy-on-select = true;
      window-inherit-working-directory = true;
      font-family = "JetBrainsMono Nerd Font Mono";
      font-thicken = true;
      adjust-cell-height = "25%";
    };
    # Material You palette → Ghostty theme. ANSI semantics (red=1, green=2,
    # blue=4) are sacrificed for visual coherence: slots map to M3 roles, so
    # 1/9 are the error role (red-ish), 4/12 are primary (coral in this
    # palette), 3/11 are tertiary (gold). `ls --color` etc. will look warm
    # rather than primary-colour. cursor/selection follow primary too.
    themes.matugen = {
      background = c "surface";
      foreground = c "on_surface";
      cursor-color = c "primary";
      cursor-text = c "on_primary";
      selection-background = c "primary_container";
      selection-foreground = c "on_primary_container";
      palette = [
        "0=${c "surface_container"}"
        "1=${c "error"}"
        "2=${c "tertiary"}"
        "3=${c "secondary"}"
        "4=${c "primary"}"
        "5=${c "primary_fixed"}"
        "6=${c "tertiary_fixed"}"
        "7=${c "on_surface_variant"}"
        "8=${c "surface_container_high"}"
        "9=${c "error_container"}"
        "10=${c "tertiary_container"}"
        "11=${c "secondary_container"}"
        "12=${c "primary_container"}"
        "13=${c "primary_fixed_dim"}"
        "14=${c "tertiary_fixed_dim"}"
        "15=${c "on_surface"}"
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

  # TUI file manager. enableZshIntegration installs the `y` shell wrapper
  # that exits yazi back into zsh at whatever directory you navigated to.
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
  };

  # TUI system monitor — top/htop replacement.
  programs.btop.enable = true;

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
