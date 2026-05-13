{ pkgs, ... }:

{
  home.username = "patrikpersson";
  home.homeDirectory = "/home/patrikpersson";
  home.stateVersion = "25.11";

  programs.git = {
    enable = true;
    settings = {
      user.name = "Patrik Persson";
      user.email = "patrikcpersson@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
    };
  };

  home.packages = with pkgs; [
    ripgrep
    fd
    bat
    eza
    jq
  ];
}
