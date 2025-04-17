#!/usr/bin/env bash

zid="$1"
passwd="$2"

if [ "${zid}" == "" ] || [ "${passwd}" == "" ]; then
  echo "run as: ./unsw-wifi.sh zXXXXXXX passwd";
  exit
fi

nmcli connection add \
  type wifi \
  connection.id eduroam \
  wifi.ssid eduroam \
  wifi.mode infrastructure \
  wifi-sec.key-mgmt wpa-eap \
  802-1x.eap peap \
  802-1x.identity "${zid}" \
  802-1x.phase2-auth mschapv2 \
  802-1x.password "${passwd}"

