# Restoring wsl from tar

```bash
wsl --import <distribution name in wsl> <location for vhdx> <tar file>

wsl -d <distribution name>

sudo vi /etc/wsl.conf
```

Then add the following to `wsl.conf`

```toml
[user]
default=your_username
```
