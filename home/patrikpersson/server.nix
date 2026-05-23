{ config, pkgs, ... }:

# Minimal home-manager entry point for headless/server hosts.
# Imports only CLI tooling — no Hyprland, theming, desktop-shell, or browser.
{
  imports = [ ./nvim.nix ./claude.nix ];

  home.username = "patrikpersson";
  home.homeDirectory = "/home/patrikpersson";
  home.stateVersion = "25.11";

  # Concatenate the z840 Environment section with the shared common rules,
  # then hand the resulting file to programs.claude-code.memory.source.
  programs.claude-code.memory.source = pkgs.writeText "CLAUDE.md" (
    builtins.readFile ./claude/CLAUDE.z840.md
    + "\n"
    + builtins.readFile ./claude/CLAUDE.common.md
  );

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

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.global.hide_env_diff = true;
  };

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
    tmux
  ];
}
