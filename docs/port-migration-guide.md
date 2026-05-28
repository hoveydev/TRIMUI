# TrimUI Port Migration Guide

A reference for migrating existing ports to the current PakUI/MinUI PortMaster firmware.
Based on the successful Stardew Valley migration (May 2026).

---

## SD Card Layout

```
/Volumes/TRIMUI/  (Mac host) = /mnt/SDCARD/  (device)

Roms/PORTS/<Display Name>.sh        ← device entry point (gitignored)
Data/ports/<Display Name>.sh        ← PortMaster mirror  (commit this)
Data/ports/<portslug>/              ← all port data      (do NOT commit — game files)
  gamedata/                         ← game binaries / assets
  dlls/                             ← patch DLLs (.dll, .dll.so)
  libs/                             ← native .so libraries
  savedata/                         ← user saves (bind-mounted at runtime)
  icon.png, bg.png, loading.png     ← UI artwork
  SVLoader.exe / launcher binary    ← runtime entry point
Apps/PortMaster/PortMaster/         ← PortMaster internals (control.txt, funcs.txt, etc.)
```

> **Git rule:** commit only launcher scripts and docs. Never commit game binaries,
> DLLs, save data, or large assets — these stay on the SD card only.

---

## Key Firmware Variables

Set by `control.txt` → `mod_TrimUI.txt`:

| Variable | Value on TrimUI | Notes |
|---|---|---|
| `$directory` | `mnt/SDCARD/Data` | **No leading slash** — prefix with `/` |
| `$HOME` | `/mnt/SDCARD/Data/home` | Overridden from system default |
| `$ESUDO` | *(empty)* | Device runs as root |
| `$GPTOKEYB` | `$controlfolder/gptokeyb $ESUDOKILL` | Controller-to-keyboard mapper |
| `$PM_CAN_MOUNT` | `Y` | bind_directories uses mount --bind |
| `$CFW_NAME` | `TrimUI` | Used to load mod_TrimUI.txt |
| `CUR_TTY` | `/dev/fd/1` | **Not** `/dev/tty0` |

---

## Common Fixes When Migrating Old Launchers

| Old pattern (broken) | New pattern (correct) | Why |
|---|---|---|
| `#!/bin/sh` + `[[ ]]` | `#!/bin/bash` | `[[ ]]` is bash-only |
| `controlfolder="../PortMaster"` | Standard discovery block (see template) | Path changed in new firmware |
| `GAMEDIR=${PWD}` | `GAMEDIR="/$directory/ports/PORTSLUG"` | PWD is unreliable; directory is absolute |
| `ln -sfv savedata ~/.config/X` | `bind_directories "$HOME/.config/X" "$GAMEDIR/savedata"` | Symlinks fail on exFAT SD card |
| `$ESUDO kill -9 $(pidof gptokeyb)` + `systemctl restart oga_events` | `pm_finish` | pm_finish handles all cleanup |
| `pic2fb loading.png` | Remove — use `pm_platform_helper` | get_controls handles splash |
| `$TASKSET mono ...` | `mono ...` | TASKSET not defined in new firmware |
| Hard-coded `/dev/tty0` | Remove | Use `CUR_TTY` or omit |

---

## Launcher Skeleton

See `docs/port-templates/launcher-template.sh` for the full annotated template.

Minimum viable launcher:

```bash
#!/bin/bash
# PORTMASTER: portslug.zip, Port Name.sh

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

GAMEDIR="/$directory/ports/PORTSLUG"
> "$GAMEDIR/log.txt" && exec > >(tee "$GAMEDIR/log.txt") 2>&1

export LD_LIBRARY_PATH="$GAMEDIR/libs:$LD_LIBRARY_PATH"
cd "$GAMEDIR"

$GPTOKEYB "BINARY" &
pm_platform_helper "BINARY"
./BINARY

pm_finish
```

---

## Mono / .NET Ports (e.g. Stardew Valley)

Extra steps needed for MonoGame/XNA ports:

1. **Verify runtime exists:**
   ```
   Apps/PortMaster/PortMaster/libs/mono-6.12.0.122-aarch64.squashfs
   ```

2. **Mount it at launch:**
   ```bash
   monofile="$controlfolder/libs/mono-6.12.0.122-aarch64.squashfs"
   monodir="$HOME/mono"
   $ESUDO mkdir -p "$monodir"
   $ESUDO umount "$monodir" 2>/dev/null || true
   $ESUDO mount -t squashfs "$monofile" "$monodir"
   export PATH="$monodir/bin:$PATH"
   ```

3. **Set Mono env vars:**
   ```bash
   export MONOGAME_PATCH="$GAMEDIR/dlls/StardewPatches.dll"  # if applicable
   export MONO_PATH="$GAMEDIR/dlls:$GAMEDIR"
   ```

4. **Launch via SVLoader (GOG Linux variant) or direct mono:**
   ```bash
   cd "$GAMEDIR/gamedata"
   mono ../SVLoader.exe "StardewValley.exe"
   ```

5. **Unmount on exit (before pm_finish):**
   ```bash
   $ESUDO umount "$HOME/mono" 2>/dev/null || true
   ```

6. **Known non-fatal error:** `GalaxyCSharpGlue DllNotFoundException` on aarch64 —
   Galaxy SDK fails silently, game continues normally. No fix required.

---

## OpenGL / gl4es Ports

For ports that use desktop OpenGL (not GLES natively), include these libs in
`$GAMEDIR/libs/` and set:

```bash
export LIBGL_ES=2
export LIBGL_GL=21
export LIBGL_FB=4
export SDL_VIDEO_GL_DRIVER="$GAMEDIR/libs/libGL.so.1"
export SDL_VIDEO_EGL_DRIVER="$GAMEDIR/libs/libEGL.so.1"
```

Required files: `libGL.so.1`, `libEGL.so.1` (gl4es), `libopenal.so.1`, `libret0.so`

---

## Save Data

Save data lives in `Data/ports/<portslug>/savedata/` on the SD card.

Bind it to wherever the game expects it:

```bash
$ESUDO mkdir -p "$HOME/.config"
bind_directories "$HOME/.config/PORTSLUG" "$GAMEDIR/savedata"
```

> `bind_directories` uses `mount --bind` on TrimUI (because `PM_CAN_MOUNT=Y`).
> Do **not** use `ln -s` — symlinks are unreliable on exFAT.

On TrimUI, `$HOME` = `/mnt/SDCARD/Data/home`, so saves land at:
`/mnt/SDCARD/Data/home/.config/PORTSLUG/`

---

## Port Artwork / Metadata

Port artwork is served from `Data/ports/gameinfo.zip` (already on the device).
The zip uses the port slug as the folder name:

```
gameinfo.zip
  stardewvalley/
    cover.png
    screenshot.jpg
    gameinfo.xml
```

No `.res` sidecar or separate icon file is needed next to the `.sh` launcher.
The frontend reads artwork directly from `gameinfo.zip` by slug.

To check if artwork already exists for your port:
```bash
unzip -l /Volumes/TRIMUI/Data/ports/gameinfo.zip | grep -i PORTSLUG
```

---

## Migration Checklist

- [ ] Create branch: `git checkout -b feature/<portslug>-port`
- [ ] Copy port source files to `Data/ports/<portslug>/` (exclude macOS `._*` files)
- [ ] Copy launcher to `Roms/PORTS/<Display Name>.sh` (not committed)
- [ ] Copy launcher to `Data/ports/<Display Name>.sh` (committed)
- [ ] Replace all old launcher patterns with new ones (see table above)
- [ ] Set `GAMEDIR="/$directory/ports/<portslug>"`
- [ ] Use `bind_directories` for save data (not `ln -s`)
- [ ] Use `pm_finish` for cleanup (not manual kill/restart)
- [ ] Add `pm_platform_helper` before launching binary (closes loading dialog)
- [ ] If Mono: mount squashfs, set PATH, unmount on exit
- [ ] If OpenGL: set gl4es env vars, ensure libs present
- [ ] Verify `gameinfo.zip` has artwork for slug
- [ ] Test on device: port appears in menu, game launches, saves persist
- [ ] Commit only launcher scripts — never game binaries or save data
