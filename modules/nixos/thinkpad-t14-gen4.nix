{ config, lib, pkgs, ... }:

{
  # ---- Graphics: Iris Xe + VA-API + oneVPL ------------------------------
  # nixos-hardware's common-gpu-intel sets the mesa baseline; iHD VA-API,
  # the oneVPL/QSV runtime, and OpenCL compute still need to be added.
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver       # iHD VA-API driver (Gen 11+ Intel iGPUs)
      vpl-gpu-rt               # oneVPL runtime (replaces onevpl-intel-gpu)
      intel-compute-runtime    # OpenCL for ffmpeg/handbrake/etc.
    ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Load i915 in initrd so the LUKS passphrase prompt renders at native res.
  boot.initrd.kernelModules = [ "i915" ];

  # GuC + HuC firmware submission. Better power use, frees the BCS engine
  # for VP9/AV1 hardware decode on Iris Xe.
  boot.kernelParams = [ "i915.enable_guc=3" ];

  # ---- Suspend wake gating ----------------------------------------------
  # The TrackPoint nub sits on an I²C HID device whose ACPI wake bit ships
  # enabled. A laptop in a bag will resume from brushed-nub events. Strip
  # the wake bit on the i2c_hid_acpi controller.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="i2c", DRIVERS=="i2c_hid_acpi", ATTR{power/wakeup}="disabled"
  '';

  # ---- Power management -------------------------------------------------
  # power-profiles-daemon is what GNOME/KDE talk to natively. It's
  # mutually exclusive with TLP. nixos-hardware's common-pc-laptop turns
  # TLP on by default, so force it off here.
  services.tlp.enable = lib.mkForce false;
  services.power-profiles-daemon.enable = true;

  # ---- Fingerprint ------------------------------------------------------
  # Synaptics Prometheus / WBF sensor. Handled by the in-tree libfprint
  # `synaptics` driver. Do NOT enable services.fprintd.tod — that path is
  # for older Validity 138a:00xx sensors and will break enrollment.
  services.fprintd.enable = true;
  # mkForce — nixos-hardware (or another module in the stack) sets these
  # to false by default; we override to enable fprintd PAM integration
  # for tty login, sudo, and the GDM password prompt.
  security.pam.services = {
    login.fprintAuth = lib.mkForce true;
    sudo.fprintAuth = lib.mkForce true;
    gdm-password.fprintAuth = lib.mkForce true;
  };

  # ---- Wi-Fi / Bluetooth ------------------------------------------------
  # AX211 + s2idle occasionally fails to reassociate when the radio's
  # power-save loop kicks in mid-resume. Keeping powersave off avoids the
  # whole class of resume-Wi-Fi-stalls without measurable battery cost.
  networking.networkmanager.wifi.powersave = false;

  hardware.bluetooth.enable = true;
  hardware.bluetooth.powerOnBoot = true;
  services.blueman.enable = true;

  # ---- Thunderbolt 4 / USB4 ---------------------------------------------
  # boltd handles user authorization of TB4 devices. Pair with BIOS
  # Thunderbolt security = "User Authorization".
  services.hardware.bolt.enable = true;

  # ---- Audio: PipeWire + WirePlumber ------------------------------------
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    wireplumber.enable = true;

    # The Realtek codec on this chassis needs ~1 s to relock the PLL after
    # the default 5 s idle suspend, producing an audible pop when audio
    # next plays. Disable the suspend timeout on every ALSA node.
    wireplumber.extraConfig."99-disable-suspend" = {
      "monitor.alsa.rules" = [{
        matches = [
          { "node.name" = "~alsa_input.*"; }
          { "node.name" = "~alsa_output.*"; }
        ];
        actions."update-props"."session.suspend-timeout-seconds" = 0;
      }];
    };

    # Audio routing policy, pinned declaratively so it survives reboots
    # and dock cycles. Two failure modes plus one preference:
    #
    # 1. This chassis' ALSA UCM splits analog output into two mutually
    #    exclusive card profiles — one exposing Speaker, one exposing
    #    Headphones. WirePlumber can settle on the Headphones profile
    #    with nothing in the jack, leaving no usable analog sink.
    #    device.profile.priority.rules (read by the find-preferred-
    #    profile hook) lists the Speaker profile first, so the built-in
    #    speakers are always the active analog output when undocked.
    # 2. The dock's USB audio sink advertises priority.session 1109,
    #    above the laptop speaker's 1000, so find-best-default-node
    #    would auto-promote it to the default sink on connect — into a
    #    dead 3.5 mm jack (the TS3 Plus has no speakers of its own).
    #    Drop it to 100. A manual `wpctl set-default` still overrides
    #    priority, so the dock jack is one command away if speakers
    #    ever get plugged into it.
    # 3. Preference: when docked, audio should follow the browser to
    #    the Acer's built-in speakers. The Acer's DisplayPort audio
    #    sink is HiFi__HDMI2__sink (confirmed by tone test — HDMI1 is
    #    the LG, which has no speakers). Bump it to 2000 so it outranks
    #    the laptop speaker and becomes the default whenever it is
    #    present; undocked, the sink is gone and the speaker (1000)
    #    wins. NOTE: HDMI2 is the Acer only while it stays on the same
    #    dock DisplayPort — swap the monitors' dock ports and it flips.
    wireplumber.extraConfig."51-dock-audio-policy" = {
      "device.profile.priority.rules" = [{
        matches = [
          { "device.name" = "alsa_card.pci-0000_00_1f.3-platform-skl_hda_dsp_generic"; }
        ];
        actions."update-props"."priorities" = [
          "HiFi (HDMI1, HDMI2, HDMI3, Mic1, Mic2, Speaker)"
          "HiFi (HDMI1, HDMI2, HDMI3, Headphones, Mic1, Mic2)"
        ];
      }];
      "monitor.alsa.rules" = [
        {
          # Dock USB audio: demote below the laptop speaker.
          matches = [
            { "node.name" = "~alsa_output.usb-CalDigit.*"; }
          ];
          actions."update-props"."priority.session" = 100;
        }
        {
          # Acer DisplayPort audio: promote above the laptop speaker so
          # it becomes the default sink whenever the dock is connected.
          matches = [
            { "node.name" = "alsa_output.pci-0000_00_1f.3-platform-skl_hda_dsp_generic.HiFi__HDMI2__sink"; }
          ];
          actions."update-props"."priority.session" = 2000;
        }
      ];
    };
  };

  # ---- TrackPoint & touchpad --------------------------------------------
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      disableWhileTyping = true;
      clickMethod = "clickfinger";
      naturalScrolling = true;
    };
  };
  hardware.trackpoint.enable = true;
  hardware.trackpoint.sensitivity = 200;

  # ---- Brightness / media keys ------------------------------------------
  # GNOME/KDE bind XF86 keys natively, but tiling WMs (Hyprland/Sway) need
  # brightnessctl on PATH. Installing it here keeps the binding portable
  # across desktop choices.
  environment.systemPackages = with pkgs; [
    brightnessctl
    playerctl
  ];

  # ---- Firmware updates -------------------------------------------------
  # LVFS / capsule updates for BIOS, fingerprint sensor, and Thunderbolt
  # firmware. nixos-hardware's common-pc-laptop already enables this; the
  # explicit assignment documents that we depend on it.
  services.fwupd.enable = true;
}
