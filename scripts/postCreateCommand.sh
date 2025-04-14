
#!/bin/sh -ex
chmod +x scripts/*.sh
./scripts/get-wsl-ip.sh
./scripts/check-openocd.sh

