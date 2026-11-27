{ config, inputs, lib, pkgs, ... }:

# An Android phone for agents: the Android Emulator, headless on KVM, with
# Chrome for Android, so a session can open papersson/apps' pages the way the
# owner's Pixel does (real Chrome, the on-screen keyboard, system bars) and
# look at them. Cloud sessions have no KVM; z840 does.
#
# How agents reach it (hosts/z840/agent-check.nix, papersson/apps
# scripts/z840.sh android):
#   - `ssh -p 2222 agent-check@z840 android <verb>` runs `android-ctl` below
#     as the `android` user: screenshots of the whole screen (keyboard and
#     system bars included), the screen's accessibility tree, taps, swipes,
#     keys, typing, opening a URL, rotating, resetting Chrome.
#   - `ssh -p 2222 -N -L 9222:10.231.0.2:9333 agent-check@z840` forwards
#     Chrome's DevTools protocol, so agent-browser drives the phone's Chrome
#     with `--cdp http://127.0.0.1:9222`. 10.231.0.2:9333 is adb's forward to
#     Chrome's `chrome_devtools_remote` socket, and the only place 2222 lets
#     a session forward to.
#
# The emulator and adb run in a network namespace of their own (10.231.0.2),
# so their loopback is theirs and z840's local services (some trust any
# local caller) are out of reach. What the phone can reach: the internet
# (previews, production) and the cloud sessions on the tailnet (tag:agent,
# so a session can open its own local stage), nothing else. z840 itself, the
# LAN and the rest of the tailnet are dropped by the firewall rules below,
# since the tailnet policy limits tag:agent to port 2222 and a browser on
# z840 must not widen that.
#
# Resources: one emulator (4 cores, 4 GiB) always on, at a low CPU and IO
# weight so CI jobs on the same box come first.
let
  # Android's SDK licences must be accepted where nixpkgs is imported, so the
  # emulator gets its own import of the unstable input (the newest emulator
  # and system images), like github-runner.nix does for the runner.
  androidPkgs = import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  };

  apiLevel = "36";
  imageType = "google_apis"; # has Chrome and Google Play services, and adb root
  abi = "x86_64";

  android = androidPkgs.androidenv.composeAndroidPackages {
    includeEmulator = true;
    includeSystemImages = true;
    platformVersions = [ apiLevel ];
    systemImageTypes = [ imageType ];
    abiVersions = [ abi ];
    buildToolsVersions = [ ];
    includeCmake = false;
  };
  sdkRoot = "${android.androidsdk}/libexec/android-sdk";
  sysdir = "system-images/android-${apiLevel}/${imageType}/${abi}/";

  home = "/var/lib/android";
  avd = "phone";
  # The phone's network namespace and the veth pair to it.
  netns = "android";
  veth = "ve-android";
  hostAddr = "10.231.0.1";
  phoneAddr = "10.231.0.2";
  # adb's forward to Chrome's DevTools socket, at phoneAddr.
  cdpPort = 9333;

  # A phone like the owner's Pixel: 1080 x 2424 at 420 dpi is 411 x 923 CSS
  # pixels, a Pixel 9's viewport. No hardware keyboard, so Android shows the
  # on-screen one.
  avdConfig = pkgs.writeText "config.ini" ''
    AvdId=${avd}
    avd.ini.displayname=${avd}
    abi.type=${abi}
    hw.cpu.arch=${abi}
    image.sysdir.1=${sysdir}
    tag.id=${imageType}
    tag.display=Google APIs
    PlayStore.enabled=false
    hw.lcd.width=1080
    hw.lcd.height=2424
    hw.lcd.density=420
    hw.initialOrientation=portrait
    hw.keyboard=no
    hw.mainKeys=no
    hw.ramSize=4096
    hw.cpu.ncore=4
    disk.dataPartition.size=8G
    hw.gpu.enabled=yes
    hw.gpu.mode=swiftshader_indirect
    hw.audioInput=no
    hw.audioOutput=no
    hw.camera.back=none
    hw.camera.front=none
    hw.accelerometer=yes
    hw.sensors.orientation=yes
    showDeviceFrame=no
    fastboot.forceColdBoot=yes
  '';
  avdIni = pkgs.writeText "${avd}.ini" ''
    avd.ini.encoding=UTF-8
    path=${home}/avd/${avd}.avd
    path.rel=avd/${avd}.avd
    target=android-${apiLevel}
  '';

  env = {
    HOME = home;
    ANDROID_HOME = sdkRoot;
    ANDROID_SDK_ROOT = sdkRoot;
    ANDROID_USER_HOME = "${home}/.android";
    ANDROID_AVD_HOME = "${home}/avd";
    # The same address inside the namespace and from z840.
    ADB_SERVER_SOCKET = "tcp:${phoneAddr}:5037";
  };

  # `android-ctl <verb>`: everything an agent does with the phone. Runs as
  # the `android` user (agent-check reaches it through the sudo rule below).
  # The caller controls the arguments and stdin; each argument is checked
  # against its own pattern, and URLs and text come on stdin so they never
  # pass through a shell on this side. On the phone's side `adb shell` joins
  # its arguments into one sh command line, so what goes there is quoted.
  androidCtl = pkgs.writeShellApplication {
    name = "android-ctl";
    runtimeInputs = [ android.platform-tools pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
    text = ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v: "export ${k}=${lib.escapeShellArg v}") env)}
      export LC_ALL=C
      cd "$HOME"

      usage() {
        cat >&2 <<'EOF'
      usage: android status                      booted?, Android and Chrome versions, screen, keyboard
             android up                          wait for boot, wake the screen, start Chrome
             android screenshot                  PNG of the whole screen on stdout
             android ui                          the screen's accessibility tree (XML) on stdout
             android tap X Y                     tap at screen pixels
             android swipe X1 Y1 X2 Y2 [MS]      swipe (scroll) over MS milliseconds
             android key KEY                     press a key: KEYCODE_BACK, KEYCODE_ENTER, 66, ...
             android text                        type the text on stdin (printable ASCII)
             android open                        open the http(s) URL on stdin in Chrome
             android rotate portrait|landscape
             android reset                       clear Chrome's data and start it again
             android restart                     reboot the phone
      EOF
        exit 2
      }
      die() { echo "android: $*" >&2; exit 1; }
      num() { [[ $1 =~ ^[0-9]{1,5}$ ]] || usage; }
      sh_quote() { printf "'%s'" "''${1//\'/\'\\\'\'}"; }

      booted() { [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; }
      wait_boot() {
        timeout 120 adb wait-for-device || die "no emulator on adb (systemctl status android-emulator)"
        for _ in $(seq 180); do
          booted && return 0
          sleep 1
        done
        die "the emulator did not finish booting in 3 minutes"
      }
      chrome() { # url
        # On a first boot the package manager may not know Chrome yet.
        for _ in $(seq 30); do
          adb shell cmd package resolve-activity -c android.intent.category.LAUNCHER com.android.chrome \
            | grep -q com.google.android.apps.chrome.Main && break
          sleep 2
        done
        adb shell am start -a android.intent.action.VIEW \
          -n com.android.chrome/com.google.android.apps.chrome.Main -d "$(sh_quote "$1")" > /dev/null
      }
      chrome_flags() {
        # Skip Chrome's first-run screens. Chrome reads this file on a
        # debuggable build, or when it is the debug app.
        adb shell "echo '_ --disable-fre --no-default-browser-check --no-first-run' > /data/local/tmp/chrome-command-line"
        adb shell am set-debug-app --persistent com.android.chrome > /dev/null
        # Granted up front, so Chrome doesn't ask for it over the first page.
        adb shell pm grant com.android.chrome android.permission.POST_NOTIFICATIONS || true
      }
      forward() {
        adb forward tcp:${toString cdpPort} localabstract:chrome_devtools_remote > /dev/null
      }
      wake() {
        adb shell input keyevent KEYCODE_WAKEUP
        adb shell wm dismiss-keyguard
      }

      verb=''${1:-}
      [ "$#" -gt 0 ] && shift
      case "$verb" in
        setup)
          # Once per boot (the emulator unit's ExecStartPost): the phone
          # stays awake and unlocked, and Chrome starts without its
          # first-run screens.
          wait_boot
          adb shell svc power stayon true
          adb shell settings put system screen_off_timeout 2147483647
          adb shell locksettings set-disabled true > /dev/null 2>&1 || true
          adb shell settings put secure show_ime_with_hard_keyboard 1
          adb shell settings put system accelerometer_rotation 0
          chrome_flags
          wake
          forward
          chrome about:blank || echo "android: Chrome did not start" >&2
          ;;
        status)
          [ "$#" -eq 0 ] || usage
          if ! booted; then echo "booted: no"; exit 1; fi
          echo "booted: yes"
          echo "android: $(adb shell getprop ro.build.version.release | tr -d '\r') (API $(adb shell getprop ro.build.version.sdk | tr -d '\r'))"
          echo "chrome: $(adb shell dumpsys package com.android.chrome | sed -n 's/^ *versionName=//p' | head -n 1 | tr -d '\r')"
          echo "screen: $(adb shell wm size | sed -n 's/^Physical size: //p' | tr -d '\r') at $(adb shell wm density | sed -n 's/^Physical density: //p' | tr -d '\r') dpi"
          echo "keyboard: $(adb shell settings get secure default_input_method | tr -d '\r')"
          if adb shell cat /proc/net/unix | grep -q '@chrome_devtools_remote'; then
            echo "cdp: Chrome is listening (forward to ${phoneAddr}:${toString cdpPort})"
          else
            echo "cdp: Chrome is not running (android up)"
          fi
          ;;
        up)
          [ "$#" -eq 0 ] || usage
          wait_boot
          wake
          forward
          if ! adb shell cat /proc/net/unix | grep -q '@chrome_devtools_remote'; then
            chrome about:blank
            for _ in $(seq 20); do
              adb shell cat /proc/net/unix | grep -q '@chrome_devtools_remote' && break
              sleep 0.5
            done
          fi
          exec "$0" status
          ;;
        screenshot)
          [ "$#" -eq 0 ] || usage
          exec adb exec-out screencap -p
          ;;
        ui)
          [ "$#" -eq 0 ] || usage
          adb exec-out uiautomator dump /dev/tty | sed 's/UI hierchary dumped to: .*$//'
          echo
          ;;
        tap)
          [ "$#" -eq 2 ] || usage
          num "$1"; num "$2"
          adb shell input tap "$1" "$2"
          ;;
        swipe)
          [ "$#" -eq 4 ] || [ "$#" -eq 5 ] || usage
          for a in "$@"; do num "$a"; done
          adb shell input swipe "$@"
          ;;
        key)
          [ "$#" -eq 1 ] || usage
          [[ $1 =~ ^(KEYCODE_[A-Z0-9_]{1,40}|[0-9]{1,3})$ ]] || usage
          adb shell input keyevent "$1"
          ;;
        text)
          [ "$#" -eq 0 ] || usage
          t=$(head -c 4000)
          [[ $t =~ ^[[:print:]]*$ ]] || die "text must be printable ASCII (input text can't type anything else)"
          [ -n "$t" ] || exit 0
          # input text reads %s as a space; a space itself would split it.
          adb shell input text "$(sh_quote "''${t// /%s}")"
          ;;
        open)
          [ "$#" -eq 0 ] || usage
          IFS= read -r url || true
          [ "''${#url}" -le 4000 ] || die "URL too long"
          [[ $url =~ ^https?://[^[:space:]\'\"\\]+$ ]] || die "expected an http(s) URL on stdin"
          wake
          chrome "$url"
          ;;
        rotate)
          [ "$#" -eq 1 ] || usage
          case "$1" in
            portrait) r=0 ;;
            landscape) r=1 ;;
            *) usage ;;
          esac
          adb shell settings put system accelerometer_rotation 0
          adb shell settings put system user_rotation "$r"
          ;;
        reset)
          [ "$#" -eq 0 ] || usage
          adb shell pm clear com.android.chrome > /dev/null
          chrome_flags
          wake
          forward
          chrome about:blank
          ;;
        restart)
          [ "$#" -eq 0 ] || usage
          # adb emu talks to the emulator's console, which only listens
          # inside the namespace; a reboot of Android works from anywhere.
          adb reboot
          echo "android: rebooting; android up waits until it has booted"
          ;;
        *)
          usage
          ;;
      esac
    '';
  };

  # tag:agent peers' tailnet addresses, so the phone can open a cloud
  # session's local stage. Entries expire unless refreshed, so a session
  # that left the tailnet drops out within two minutes.
  agentPeers = pkgs.writeShellApplication {
    name = "android-agent-peers";
    runtimeInputs = [ config.services.tailscale.package pkgs.jq pkgs.ipset pkgs.coreutils ];
    text = ''
      while true; do
        tailscale status --json 2>/dev/null \
          | jq -r '.Peer // {} | .[] | select((.Tags // []) | index("tag:agent")) | .TailscaleIPs[]? | select(test("^100\\."))' \
          | while read -r ip; do ipset add -exist android-agents "$ip" timeout 120; done || true
        sleep 20
      done
    '';
  };
in
{
  options.z840.androidCtl = lib.mkOption {
    type = lib.types.package;
    internal = true;
    readOnly = true;
    default = androidCtl;
    description = "The android-ctl program agent-check runs as the android user.";
  };

  config = {
    users.groups.android = { };
    users.users.android = {
      isSystemUser = true;
      group = "android";
      extraGroups = [ "kvm" ];
      inherit home;
      createHome = true;
    };

    environment.systemPackages = [ android.platform-tools androidCtl ];

    # agent-check may run exactly android-ctl as the android user.
    security.sudo.extraRules = [{
      users = [ "agent-check" ];
      runAs = "android";
      commands = [{ command = lib.getExe androidCtl; options = [ "NOPASSWD" ]; }];
    }];

    # The phone's own network namespace. The emulator talks to its helpers
    # (netsimd, gRPC, adb) over loopback on ports it picks, and z840's own
    # loopback holds services that trust any local caller, so the emulator
    # and adb get a loopback of their own. A veth pair links the namespace
    # (10.231.0.2) to z840 (10.231.0.1); the firewall below decides where its
    # traffic may go, and NAT takes it out.
    systemd.services.android-netns = {
      description = "Network namespace for the Android emulator";
      wantedBy = [ "multi-user.target" ];
      before = [ "android-adb.service" "android-emulator.service" ];
      after = [ "network.target" ];
      path = [ pkgs.iproute2 ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ip netns delete ${netns} 2>/dev/null || true
        ip link delete ${veth} 2>/dev/null || true
        ip netns add ${netns}
        ip link add ${veth} type veth peer name eth0 netns ${netns}
        ip addr add ${hostAddr}/30 dev ${veth}
        ip link set ${veth} up
        ip -n ${netns} link set lo up
        ip -n ${netns} addr add ${phoneAddr}/30 dev eth0
        ip -n ${netns} link set eth0 up
        ip -n ${netns} route add default via ${hostAddr}
        [ "$(cat /proc/sys/net/ipv4/ip_forward)" = 1 ] \
          || echo "android-netns: net.ipv4.ip_forward is 0, so the phone has no internet" >&2
      '';
      preStop = ''
        ip netns delete ${netns} || true
        ip link delete ${veth} 2>/dev/null || true
      '';
    };

    # adb's server, inside the namespace on all its interfaces (-a), so z840
    # reaches it, and Chrome's DevTools forward, at ${phoneAddr}. The emulator
    # registers with it, and its key in ~/.android is the one the emulator's
    # image trusts.
    systemd.services.android-adb = {
      description = "adb server for the Android emulator";
      wantedBy = [ "multi-user.target" ];
      bindsTo = [ "android-netns.service" ];
      after = [ "android-netns.service" ];
      environment = env;
      # A crash loop gives up after five tries in ten minutes.
      startLimitIntervalSec = 600;
      startLimitBurst = 5;
      serviceConfig = {
        User = "android";
        Group = "android";
        WorkingDirectory = home;
        NetworkNamespacePath = "/run/netns/${netns}";
        # adb refuses a host in -L ("listening on specified hostname currently
        # unsupported"); -a listens on every interface of the namespace.
        ExecStart = "${android.platform-tools}/bin/adb -a -L tcp:5037 nodaemon server";
        Restart = "always";
        RestartSec = 10;
      };
    };

    systemd.services.android-emulator = {
      description = "Android emulator (headless phone for agents)";
      wantedBy = [ "multi-user.target" ];
      requires = [ "android-adb.service" ];
      bindsTo = [ "android-netns.service" ];
      after = [ "android-adb.service" "android-netns.service" ];
      environment = env;
      startLimitIntervalSec = 1800;
      startLimitBurst = 5;
      path = [ pkgs.coreutils ];
      preStart = ''
        mkdir -p avd/${avd}.avd .android
        install -m 644 ${avdIni} avd/${avd}.ini
        install -m 644 ${avdConfig} avd/${avd}.avd/config.ini
        # A new system image can't boot the old one's data: wipe it when the
        # image changes.
        if [ "$(cat avd/image 2>/dev/null)" != ${sdkRoot}/${sysdir} ]; then
          rm -rf avd/${avd}.avd/*.img avd/${avd}.avd/*.qcow2 avd/${avd}.avd/snapshots
          echo ${sdkRoot}/${sysdir} > avd/image
        fi
      '';
      serviceConfig = {
        User = "android";
        Group = "android";
        SupplementaryGroups = [ "kvm" ];
        WorkingDirectory = home;
        NetworkNamespacePath = "/run/netns/${netns}";
        ExecStart = lib.concatStringsSep " " [
          "${sdkRoot}/emulator/emulator"
          "-avd ${avd} -port 5554"
          "-no-window -no-audio -no-boot-anim -no-snapshot -no-metrics"
          "-gpu swiftshader_indirect -accel on"
          # The namespace can't use z840's resolver (Tailscale's 100.100.100.100,
          # which the firewall drops), so the phone asks public ones.
          "-dns-server 1.1.1.1,9.9.9.9"
        ];
        ExecStartPost = "${lib.getExe androidCtl} setup";
        TimeoutStartSec = 600;
        Restart = "always";
        RestartSec = 10;
        # CI first: the emulator gets CPU and disk only when they are spare.
        CPUWeight = 20;
        IOWeight = 20;
        Nice = 10;
        MemoryMax = "8G";
      };
    };

    systemd.services.android-agent-peers = {
      description = "Let the Android emulator reach tag:agent sessions on the tailnet";
      wantedBy = [ "multi-user.target" ];
      after = [ "tailscaled.service" "firewall.service" ];
      serviceConfig = {
        ExecStart = lib.getExe agentPeers;
        Restart = "always";
        RestartSec = 10;
      };
    };

    # Where the phone's traffic may go: the internet and agent sessions.
    # New connections from the namespace to z840 itself (any of its
    # addresses), the LAN, link-local, multicast and the rest of the tailnet
    # are dropped. This is in mangle PREROUTING, before the filter table,
    # because tailscaled's own FORWARD rules accept anything bound for
    # tailscale0 and may sit ahead of ours.
    networking.firewall.extraPackages = [ pkgs.ipset ];
    networking.firewall.extraCommands = ''
      # The first version filtered the android user's OUTPUT instead.
      iptables -w -D OUTPUT -m owner --uid-owner android -j android-out 2>/dev/null || true
      ip6tables -w -D OUTPUT -m owner --uid-owner android -j android-out 2>/dev/null || true
      iptables -w -X android-out 2>/dev/null || true
      ip6tables -w -X android-out 2>/dev/null || true

      ipset create -exist android-agents hash:ip timeout 120
      iptables -w -t mangle -N android-in 2>/dev/null || true
      iptables -w -t mangle -F android-in
      iptables -w -t mangle -A android-in -m conntrack ! --ctstate NEW -j RETURN
      iptables -w -t mangle -A android-in -m set --match-set android-agents dst -j RETURN
      iptables -w -t mangle -A android-in -m addrtype --dst-type LOCAL -j DROP
      for net in 10.0.0.0/8 100.64.0.0/10 169.254.0.0/16 172.16.0.0/12 192.168.0.0/16 224.0.0.0/4 240.0.0.0/4; do
        iptables -w -t mangle -A android-in -d "$net" -j DROP
      done
      iptables -w -t mangle -D PREROUTING -i ${veth} -j android-in 2>/dev/null || true
      iptables -w -t mangle -I PREROUTING -i ${veth} -j android-in
      iptables -w -t nat -D POSTROUTING -s ${phoneAddr}/32 ! -o ${veth} -j MASQUERADE 2>/dev/null || true
      iptables -w -t nat -A POSTROUTING -s ${phoneAddr}/32 ! -o ${veth} -j MASQUERADE
    '';
    networking.firewall.extraStopCommands = ''
      iptables -w -t mangle -D PREROUTING -i ${veth} -j android-in 2>/dev/null || true
      iptables -w -t nat -D POSTROUTING -s ${phoneAddr}/32 ! -o ${veth} -j MASQUERADE 2>/dev/null || true
    '';
  };
}
