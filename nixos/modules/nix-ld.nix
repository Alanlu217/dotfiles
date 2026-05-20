{ pkgs, ... }:
{
  nixpkgs.config.allowUnfree = true;
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      # ── Core / libc ──────────────────────────────────────────────
      stdenv.cc.cc      # libstdc++
      glibc
      zlib
      zstd
      bzip2
      xz
      lz4
      libgcc

      # ── Crypto / security ────────────────────────────────────────
      openssl
      libsodium
      nss
      nspr
      gnutls
      p11-kit

      # ── Networking ───────────────────────────────────────────────
      curl
      libssh
      nghttp2

      # ── Filesystem / OS ──────────────────────────────────────────
      attr
      acl
      util-linux
      e2fsprogs
      fuse
      systemd          # libsystemd, libudev
      coreutils
      libcap

      # ── XML / data ───────────────────────────────────────────────
      libxml2
      expat

      # ── Compression (extra) ──────────────────────────────────────
      zlib

      # ── Display / X11 ────────────────────────────────────────────
      libx11
      libxext
      libxfixes
      libxrender
      libxrandr
      libxcomposite
      libxdamage
      libxtst
      libxi
      libxinerama
      libxcursor
      libxxf86vm
      libxcb
      libxshmfence
      libSM
      libICE

      # ── Wayland ──────────────────────────────────────────────────
      wayland
      libxkbcommon

      # ── OpenGL / GPU ─────────────────────────────────────────────
      libGL
      libGLU
      libva
      libdrm
      libgbm
      mesa
      vulkan-loader

      # ── Audio ────────────────────────────────────────────────────
      alsa-lib
      pipewire
      pulseaudio      # libpulse
      jack2           # libjack

      # ── GTK / GLib stack ─────────────────────────────────────────
      glib
      gtk2
      gtk3
      gtk4
      gdk-pixbuf
      atk
      pango
      cairo
      harfbuzz
      at-spi2-core    # accessibility
      at-spi2-atk

      # ── Fonts ────────────────────────────────────────────────────
      fontconfig
      freetype

      # ── D-Bus / IPC ──────────────────────────────────────────────
      dbus
      dbus-glib

      # ── Desktop integration ──────────────────────────────────────
      gnome2.GConf
      cups
      networkmanager

      # ── Multimedia ───────────────────────────────────────────────
      ffmpeg
      libvdpau
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base

      # ── Input / USB / hardware ───────────────────────────────────
      libusb1
      udev            # usually via systemd above
      pciutils
      libelf

      # ── compat shims ─────────────────────────────────────────────
      libxcrypt            # modern libcrypt.so.2
      libxcrypt-legacy     # old libcrypt.so.1 (some older binaries)

      # ── Misc / AppImage / games ──────────────────────────────────
      SDL2
      SDL2_mixer
      SDL2_image
      zenity
    ];
  };
}
