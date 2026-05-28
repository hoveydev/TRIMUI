#!/bin/sh
cd "$(dirname "$0")"
if [ -f "./wifi_enabled" ]; then
    rfkill unblock wifi 2>/dev/null
    ip link set wlan0 up
    sleep 1
    NETWORKS_DIR="./networks"
    CONFIG_FILE="/etc/wifi/wpa_supplicant.conf"
    has_ip_address() {
        ip addr show wlan0 | grep -q "inet "
    }
    connected=0
    for conf_file in "$NETWORKS_DIR"/*.conf; do
        [ -f "$conf_file" ] || continue
        ssid=$(grep 'ssid=' "$conf_file" | cut -d'"' -f2)
        [ -z "$ssid" ] && continue
        cat > "$CONFIG_FILE" << CFG
ctrl_interface=/etc/wifi/sockets
update_config=1

$(cat "$conf_file")
CFG
        killall -q wpa_supplicant
        killall -q udhcpc
        sleep 1
        wpa_supplicant -B -i wlan0 -c "$CONFIG_FILE"
        sleep 2
        (udhcpc -i wlan0 -n) &
        attempt=0
        while [ $attempt -lt 10 ]; do
            has_ip_address && connected=1 && break
            attempt=$((attempt + 1))
            sleep 0.5
        done
        [ $connected -eq 1 ] && break
    done
    [ $connected -eq 0 ] && wpa_supplicant -B -i wlan0 -c "$CONFIG_FILE"
else
    ip link set wlan0 down
    killall -q wpa_supplicant
    killall -q udhcpc
fi
