{pkgs, ...}: {
  security.rtkit.enable = true;
  software.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  services.udisks2.enable = true;

  environment.systemPackages = with pkgs; [
    pavucontrol
    networkmanagerapplet
    brightnessctl
    udiskie
  ];
}
