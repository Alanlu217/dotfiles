# My dotfiles

Clone into home directory.

## Computer Audio Issues yoga9
```
echo "options snd-sof-intel-hda-generic hda_model=alc287-yoga9-bass-spk-pin" > /etc/modprobe.d/sound.conf
```

## IWD Network Conf
```
echo '[General]
EnableNetworkConfiguration=true
[Network]
NameResolvingService=systemd
EnableIPv6=true' | sudo tee /etc/iwd/main.conf
```

## Package dependencies
See [justfile](justfile)

## Flags for electron apps
```
--use-gl=desktop --ozone-platform-hint=wayland
```

## Xwayland-satellite Steam
Turn off web gpu in steam settings (top left is settings)
