#!/usr/bin/env sh

dim="$(slurp -d)"

grim -g "$dim" - | wl-copy
