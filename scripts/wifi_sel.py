#!/usr/bin/env python3

import subprocess

result = subprocess.run(["nmcli", "c", "show"], capture_output=True, text=True)

raw_connections = result.stdout.splitlines()[1:]
connections = []

for i, c in enumerate(raw_connections):
    conn = c.split()
    if conn[2] == "wifi":
        connections.append(conn[0])
c = "\n".join(connections)
result = subprocess.run(["rofi", "-dmenu"], input=c, capture_output=True, text=True)

target = result.stdout.strip()

result = subprocess.run(["nmcli", "c", "up", target])
