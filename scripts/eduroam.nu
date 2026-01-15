#!/usr/bin/env nu

def main [zid: string] {
  let password = (input -s "password: ")
  print ""

  do --ignore-errors {
    nmcli c delete eduroam | ignore
  }

  nmcli ...[c add
    type wifi
    connection.id eduroam
    wifi.ssid eduroam
    wifi.mode infrastructure
    wifi-sec.key-mgmt wpa-eap
    802-1x.eap peap
    802-1x.identity $"($zid)"
    802-1x.phase2-auth mschapv2
    802-1x.password $"($password)"
  ]
}

