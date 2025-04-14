#!/bin/bash

if [ ! -f "/mnt/c/OpenOCD/openocd.exe" ]; then
    echo "OpenOCD not found, attempting to install..."
    ./install-openocd.sh
    if [ $? -ne 0 ]; then
        echo "Failed to install OpenOCD"
        exit 1
    fi
fi

echo "OpenOCD found at: C:\OpenOCD\openocd.exe"
exit 0
