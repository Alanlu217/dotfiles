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

## Xwayland-satellite Steam
Turn off web gpu in steam settings (top left is settings)
