# My dotfiles

Clone into home directory.

## Computer Audio Issues yoga9
cat /etc/modprobe.d/sound.conf
```
options snd-sof-intel-hda-generic hda_model=alc287-yoga9-bass-spk-pin
```

## Package dependencies
See [justfile](justfile)

## Flags for electron apps
```
--use-gl=desktop --ozone-platform-hint=wayland
```

ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILqBIc+2of0E8TCKsOCGjT2SKHQcnZRpiW2dOnW6d1pV
