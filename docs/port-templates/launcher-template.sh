#!/bin/bash
# PORTMASTER: PORTSLUG.zip, PORT DISPLAY NAME.sh
#
# Template for PortMaster-compatible launchers on TrimUI Smart Pro (PakUI/MinUI firmware).
# Copy this file, replace all PLACEHOLDER values, and drop it in:
#   - Roms/PORTS/<Display Name>.sh        (device runtime entry point, gitignored)
#   - Data/ports/<Display Name>.sh        (PortMaster mirror, committed to git)
#
# Port data goes in:  Data/ports/PORTSLUG/
# Save data goes in:  Data/ports/PORTSLUG/savedata/
#
# ─── PLACEHOLDERS ─────────────────────────────────────────────────────────────
# PORTSLUG       lowercase slug, no spaces (e.g. stardewvalley)
# DISPLAY_NAME   human-readable name      (e.g. Stardew Valley)
# BINARY         executable name          (e.g. StardewValley.exe, game.bin)
# ──────────────────────────────────────────────────────────────────────────────

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

# ── PortMaster controlfolder discovery ────────────────────────────────────────
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

# ── Paths ─────────────────────────────────────────────────────────────────────
# $directory is set by control.txt to "mnt/SDCARD/Data" (no leading slash).
# On TrimUI, $HOME is overridden to /mnt/SDCARD/Data/home by mod_TrimUI.txt.
GAMEDIR="/$directory/ports/PORTSLUG"

# Redirect stdout/stderr to log for debugging
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

# ── [OPTIONAL] Mono runtime ───────────────────────────────────────────────────
# Uncomment this block for .NET/MonoGame ports.
#
# monofile="$controlfolder/libs/mono-6.12.0.122-aarch64.squashfs"
# if [ ! -f "$monofile" ]; then
#   pm_message "Mono runtime not found. Please ensure PortMaster runtimes are installed."
#   sleep 5
#   exit 1
# fi
# monodir="$HOME/mono"
# $ESUDO mkdir -p "$monodir"
# if [[ "$PM_CAN_MOUNT" != "N" ]]; then
#   $ESUDO umount "$monodir" 2>/dev/null || true
# fi
# $ESUDO mount -t squashfs "$monofile" "$monodir"
# export PATH="$monodir/bin:$PATH"

# ── [OPTIONAL] Save data binding ──────────────────────────────────────────────
# Use bind_directories to map a savedata/ subfolder to where the game expects saves.
# On TrimUI, PM_CAN_MOUNT=Y so this uses mount --bind (works on exFAT SD cards).
# Symlinks do NOT work reliably on exFAT — always use bind_directories.
#
# $ESUDO mkdir -p "$HOME/.config"
# bind_directories "$HOME/.config/PORTSLUG" "$GAMEDIR/savedata"

# ── Runtime environment ───────────────────────────────────────────────────────
export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"

# ── [OPTIONAL] OpenGL-over-GLES (gl4es) ──────────────────────────────────────
# Needed for ports that use desktop OpenGL (not GLES natively).
# Requires libGL.so.1 and libEGL.so.1 in $GAMEDIR/libs/.
#
# export LIBGL_ES=2
# export LIBGL_GL=21
# export LIBGL_FB=4
# export SDL_VIDEO_GL_DRIVER="$GAMEDIR/libs/libGL.so.1"
# export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/libs/libEGL.so.1"

cd "$GAMEDIR"

# ── Launch ────────────────────────────────────────────────────────────────────
$GPTOKEYB "BINARY" &
pm_platform_helper "BINARY"

# Native binary example:
# ./BINARY

# Mono/.NET example:
# cd "$GAMEDIR/gamedata"
# mono ../SVLoader.exe "BINARY"

# ── Cleanup ───────────────────────────────────────────────────────────────────
# $ESUDO umount "$HOME/mono" 2>/dev/null || true  # if mono was mounted
pm_finish
