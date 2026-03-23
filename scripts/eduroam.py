#!/usr/bin/env python3
import sys
import getpass
import subprocess


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <zid>")
        sys.exit(1)

    zid = sys.argv[1]
    password = getpass.getpass("password: ")

    # Delete existing eduroam connection, ignoring errors
    subprocess.run(["nmcli", "c", "delete", "eduroam"], capture_output=True)

    # Add new eduroam connection
    subprocess.run(
        [
            "nmcli",
            "c",
            "add",
            "type",
            "wifi",
            "connection.id",
            "eduroam",
            "wifi.ssid",
            "eduroam",
            "wifi.mode",
            "infrastructure",
            "wifi-sec.key-mgmt",
            "wpa-eap",
            "802-1x.eap",
            "peap",
            "802-1x.identity",
            zid,
            "802-1x.phase2-auth",
            "mschapv2",
            "802-1x.password",
            password,
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
