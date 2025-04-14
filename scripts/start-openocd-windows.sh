#!/bin/bash

OPENOCD_PATH="/mnt/c/OpenOCD"
BAT_FILE="$OPENOCD_PATH/start-openocd.bat"
WSL_MONITOR="$OPENOCD_PATH/wsl-monitor.sh"
WINDOWS_MONITOR="$OPENOCD_PATH/windows-monitor.ps1"
START_MONITORS="$OPENOCD_PATH/start-monitors.bat"
CONTAINER_TRIGGER="$OPENOCD_PATH/container_trigger.txt"
WINDOWS_TRIGGER="$OPENOCD_PATH/windows_trigger.txt"
WSL_LOG="$OPENOCD_PATH/wsl-monitor.log"
WINDOWS_LOG="$OPENOCD_PATH/windows-monitor.log"

# Function to handle cleanup on exit
cleanup() {
    echo -e "\nCancelling OpenOCD setup..."
    rm -f "$CONTAINER_TRIGGER" "$WINDOWS_TRIGGER"
    exit 1
}

# Set up trap for Ctrl+C
trap cleanup SIGINT

# Clean up any existing trigger files
rm -f "$CONTAINER_TRIGGER" "$WINDOWS_TRIGGER"

# Check if OpenOCD exists
if [ ! -f "$OPENOCD_PATH/openocd.exe" ]; then
    echo "OpenOCD not found, running installation..."
    ./check-openocd.sh
fi

# Create OpenOCD batch file if it doesn't exist
echo "Creating start-openocd.bat..."
cat > "$BAT_FILE" << 'EOL'
@echo off
cd /d %~dp0
openocd.exe -c "bindto 0.0.0.0" -c "telnet_port 4444" -s "openocd/scripts" -f interface/stlink-v2-1.cfg -f target/stm32f4x.cfg -c "set FLASH_BREAKPOINTS 1"
EOL

# Create WSL monitor script
echo "Creating WSL monitor script..."
cat > "$WSL_MONITOR" << 'EOL'
#!/bin/bash
TRIGGER_FILE="/mnt/c/OpenOCD/container_trigger.txt"
WINDOWS_TRIGGER="/mnt/c/OpenOCD/windows_trigger.txt"

# Clean up any existing triggers
rm -f "$TRIGGER_FILE" "$WINDOWS_TRIGGER"

echo "WSL Monitor started" > /mnt/c/OpenOCD/wsl-monitor.log

echo "================================================================"
echo "                     WSL Monitor Started                          "
echo "================================================================"
echo
echo "WSL monitor is ready and waiting for triggers..."
echo "You can safely close this window now."
echo
echo "================================================================"

while true; do
    if [ -f "$TRIGGER_FILE" ]; then
        echo "Trigger file detected" >> /mnt/c/OpenOCD/wsl-monitor.log
        rm -f "$TRIGGER_FILE"
        touch "$WINDOWS_TRIGGER"
        echo "Windows trigger created" >> /mnt/c/OpenOCD/wsl-monitor.log
    fi
    sleep 1
done
EOL
chmod +x "$WSL_MONITOR"

# Create Windows PowerShell monitor script
echo "Creating Windows monitor script..."
cat > "$WINDOWS_MONITOR" << 'EOL'
Clear-Host
Write-Host "================================================================"
Write-Host "                    OpenOCD Windows Monitor                       "
Write-Host "================================================================"
Write-Host ""

Start-Transcript -Path "C:\OpenOCD\windows-monitor.log" -Append > $null

# Clean up any existing triggers
if (Test-Path "C:\OpenOCD\container_trigger.txt") { Remove-Item "C:\OpenOCD\container_trigger.txt" }
if (Test-Path "C:\OpenOCD\windows_trigger.txt") { Remove-Item "C:\OpenOCD\windows_trigger.txt" }

$triggerFile = "C:\OpenOCD\windows_trigger.txt"
$watcher = New-Object System.IO.FileSystemWatcher
$watcher.Path = "C:\OpenOCD"
$watcher.Filter = "windows_trigger.txt"
$watcher.EnableRaisingEvents = $true

Write-Host "Windows Monitor started and waiting for triggers..."
Write-Host ""

$action = {
    Write-Host "Trigger detected, starting OpenOCD..."
    Remove-Item $triggerFile
    Start-Process "C:\OpenOCD\start-openocd.bat"
}

$created = Register-ObjectEvent $watcher Created -Action $action

while ($true) { Start-Sleep 1 }
EOL

# Create batch file to start monitors
echo "Creating start-monitors batch file..."
cat > "$START_MONITORS" << 'EOL'
@echo off
cls
echo ================================================================
echo                   OpenOCD Monitor Setup
echo ================================================================
echo.
echo Starting monitors...
echo.

echo [1/2] Starting PowerShell monitor...
start /min powershell.exe -ExecutionPolicy Bypass -File "%~dp0\windows-monitor.ps1"
timeout /t 1 > nul

echo [2/2] Starting WSL monitor...
wsl -e bash -c "/mnt/c/OpenOCD/wsl-monitor.sh"
timeout /t 1 > nul

echo.
echo ================================================================
echo                        Status Check
echo ================================================================
echo.

if exist "%~dp0\windows-monitor.log" (
    echo [  OK  ] Windows monitor is running
) else (
    echo [FAILED] Windows monitor failed to start
)

if exist "%~dp0\wsl-monitor.log" (
    echo [  OK  ] WSL monitor is running
) else (
    echo [FAILED] WSL monitor failed to start
)

echo.
echo ================================================================
echo                   Setup Complete
echo ================================================================
echo.
echo Monitors are running and ready for OpenOCD commands.
echo You can safely close this window now.
echo.
echo Press any key to exit...
pause > nul
EOL

# Show debug info
clear
echo "================================================================"
echo "                     OpenOCD Setup Status                         "
echo "================================================================"
echo "Checking files:"
echo "- start-openocd.bat exists: $([ -f "$BAT_FILE" ] && echo "[  OK  ]" || echo "[FAILED]")"
echo "- wsl-monitor.sh exists: $([ -f "$WSL_MONITOR" ] && echo "[  OK  ]" || echo "[FAILED]")"
echo "- windows-monitor.ps1 exists: $([ -f "$WINDOWS_MONITOR" ] && echo "[  OK  ]" || echo "[FAILED]")"
echo "- start-monitors.bat exists: $([ -f "$START_MONITORS" ] && echo "[  OK  ]" || echo "[FAILED]")"
echo ""
echo "================================================================"
echo "                     IMPORTANT SETUP STEPS                         "
echo "================================================================"
echo "1. Open Windows Explorer"
echo "2. Navigate to: C:\OpenOCD"
echo "3. Double-click 'start-monitors.bat'"
echo "4. Wait for both monitors to show [OK]"
echo "5. Type yes/y/ja/j to continue, or no/n/nee to cancel"
echo "================================================================"

# Read user input with timeout
read -t 300 -p "Have you completed these steps? (yes/y/ja/j) " response
response_lower="${response,,}"  # Convert to lowercase
if [[ ! "$response_lower" =~ ^(yes|y|ja|j)$ ]]; then
    if [[ "$response_lower" =~ ^(no|n|nee)$ ]]; then
        echo -e "\nSetup cancelled by user."
    else
        echo -e "\nInvalid response or timeout. Setup cancelled."
    fi
    cleanup
fi

# Try to start OpenOCD
echo "Starting OpenOCD..."
rm -f "$CONTAINER_TRIGGER" "$WINDOWS_TRIGGER"
touch "$CONTAINER_TRIGGER"

# Check if the trigger was picked up
sleep 2
if [ -f "$CONTAINER_TRIGGER" ]; then
    echo "ERROR: Monitors don't seem to be running."
    echo ""
    echo "Please make sure you've started the monitors by running:"
    echo "C:\OpenOCD\start-monitors.bat"
    cleanup
else
    echo "OpenOCD is starting..."
fi
