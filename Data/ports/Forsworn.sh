#!/bin/bash
# PORTMASTER: forsworn.zip, Forsworn.sh

# PortMaster preamble
XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}
if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi
source $controlfolder/control.txt
[ -f "${controlfolder}/mod_${CFW_NAME}.txt" ] && source "${controlfolder}/mod_${CFW_NAME}.txt"
get_controls

# Adjust these to your paths and desired godot version
GAMEDIR=/$directory/ports/forsworn
godot_runtime="godot_4.5"
godot_executable="godot45.$DEVICE_ARCH"
pck_filename="Forsworn.pck"
gptk_filename="forsworn.gptk"

# Logging
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# Create directory for save files
CONFDIR="$GAMEDIR/conf/"
$ESUDO mkdir -p "${CONFDIR}"


if [[ "$CFW_NAME" = "ROCKNIX" ]]; then
    if ! glxinfo | grep "OpenGL version string"; then
    pm_message "This Port does not support the libMali graphics driver. Switch to Panfrost to continue."
    sleep 5
    exit 1
    fi
fi

# Mount Weston runtime
weston_dir=/tmp/weston
$ESUDO mkdir -p "${weston_dir}"
weston_runtime="weston_pkg_0.2"
if [ ! -f "$controlfolder/libs/${weston_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${weston_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${weston_dir}"
fi
$ESUDO mount "$controlfolder/libs/${weston_runtime}.squashfs" "${weston_dir}"

# Mount Godot runtime
godot_dir=/tmp/godot
$ESUDO mkdir -p "${godot_dir}"
if [ ! -f "$controlfolder/libs/${godot_runtime}.squashfs" ]; then
  if [ ! -f "$controlfolder/harbourmaster" ]; then
    pm_message "This port requires the latest PortMaster to run, please go to https://portmaster.games/ for more info."
    sleep 5
    exit 1
  fi
  $ESUDO $controlfolder/harbourmaster --quiet --no-check runtime_check "${godot_runtime}.squashfs"
fi
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
    $ESUDO umount "${godot_dir}"
fi
$ESUDO mount "$controlfolder/libs/${godot_runtime}.squashfs" "${godot_dir}"

cd $GAMEDIR

$GPTOKEYB "$godot_executable" -c "$GAMEDIR/$gptk_filename" &

# PakUI/TrimUI: udev doesn't tag input devices with ID_INPUT, causing Weston to
# abort with "failed to create input devices". Add a temporary udev rule to tag
# all input event devices so Weston can start normally.
if [[ "$CFW_NAME" == "TrimUI" ]]; then
  mkdir -p /run/udev/rules.d 2>/dev/null
  echo 'KERNEL=="event[0-9]*", SUBSYSTEM=="input", ENV{ID_INPUT}="1", ENV{ID_INPUT_KEY}="1"' \
    > /run/udev/rules.d/99-trimui-weston-input.rules
  udevadm control --reload-rules 2>/dev/null || true
  udevadm trigger --subsystem-match=input 2>/dev/null || true
  sleep 1
  $ESUDO mkdir -p /tmp/weston_runtime
  $ESUDO chmod 700 /tmp/weston_runtime
  pm_platform_helper "$godot_dir/$godot_executable"
  $ESUDO env CRUSTY_BLOCK_INPUT=1 $weston_dir/westonwrap.sh headless noop kiosk crusty_x11egl \
  LD_PRELOAD= XDG_DATA_HOME=$CONFDIR $godot_dir/$godot_executable \
  --resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f \
  --rendering-driver opengl3_es --audio-driver ALSA --main-pack $GAMEDIR/gamedata/$pck_filename
else
  # Start Westonpack and Godot
  # Put CRUSTY_SHOW_CURSOR=1 after "env" if you need a mouse cursor
  # LD_PRELOAD is put here because Godot runtime links against libEGL.so, and crusty is interfering with that on some systems.
  $ESUDO env CRUSTY_BLOCK_INPUT=1 $weston_dir/westonwrap.sh headless noop kiosk crusty_x11egl \
  LD_PRELOAD= XDG_DATA_HOME=$CONFDIR $godot_dir/$godot_executable \
  --resolution ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} -f \
  --rendering-driver opengl3_es --audio-driver ALSA --main-pack $GAMEDIR/gamedata/$pck_filename
fi

#Clean up after ourselves
$ESUDO $weston_dir/westonwrap.sh cleanup
if [[ "$PM_CAN_MOUNT" != "N" ]]; then
  $ESUDO umount "${weston_dir}"
  $ESUDO umount "${godot_dir}"
fi

pm_finish