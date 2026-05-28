#!/bin/sh

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

PICKER="./picker"
SHOW_MESSAGE="./show_message"

ROMS_BASE="/mnt/SDCARD/Roms"
MENU_TXT="$ROMS_BASE/to_remove (CUSTOM)/menu.txt"

MAIN_MENU="/tmp/rom_manager_main.txt"
LIST_MENU="/tmp/rom_manager_list.txt"
BROWSE_MENU="/tmp/rom_manager_browse.txt"

trap 'rm -f "$MAIN_MENU" "$LIST_MENU" "$BROWSE_MENU"' EXIT

# -------------------------------------------------------------------
# Shared: delete a ROM file and its .res image
# Usage: delete_rom <full_rom_path>
# -------------------------------------------------------------------
delete_rom() {
    local rom_path="$1"
    local rom_dir rom_file img_path

    rom_dir="$(dirname "$rom_path")"
    rom_file="$(basename "$rom_path")"
    img_path="$rom_dir/.res/$rom_file.png"

    rm -f "$rom_path"
    rm -f "$img_path"
}

# -------------------------------------------------------------------
# Shared: remove a line from menu.txt that matches the given rom path
# Usage: remove_from_menu_txt <full_rom_path>
# -------------------------------------------------------------------
remove_from_menu_txt() {
    local rom_path="$1"
    local tmp="/tmp/menu_txt_clean.txt"

    [ -f "$MENU_TXT" ] || return
    grep -v "|$rom_path|" "$MENU_TXT" > "$tmp" && mv "$tmp" "$MENU_TXT"
}

# -------------------------------------------------------------------
# Mode 1: Delete from List
# -------------------------------------------------------------------
mode_delete_from_list() {
    while true; do
        # Build menu from menu.txt, only showing entries whose ROM exists
        > "$LIST_MENU"
        echo "Delete from List|__HEADER__|header" >> "$LIST_MENU"

        local found=0
        while IFS='|' read -r name path action; do
            # Skip header, blank lines, and collection markers
            [ -z "$name" ] && continue
            [ "$action" = "menu_options" ] && continue
            [ "$action" != "launch" ] && continue

            # Convert device path to local path for existence check
            local local_path
            local_path="$(echo "$path" | sed 's|/mnt/SDCARD|/mnt/SDCARD|g')"

            # Only include if file exists
            [ -f "$local_path" ] || continue

            local system
            system="$(echo "$path" | sed 's|.*/Roms/||' | sed 's|/.*||')"
            echo "$name [$system]|$path|delete" >> "$LIST_MENU"
            found=$((found + 1))
        done < "$MENU_TXT"

        if [ "$found" -eq 0 ]; then
            "$SHOW_MESSAGE" "Delete from List|No pending ROMs found.|All entries may already be deleted." -l a
            return
        fi

        local sel st
        sel="$("$PICKER" "$LIST_MENU" -a "DELETE" -b "BACK")"
        st=$?

        [ $st -eq 1 ] || [ -z "$sel" ] && return

        local action
        action="$(echo "$sel" | cut -d'|' -f3)"
        [ "$action" = "header" ] && continue

        local game_name rom_path
        game_name="$(echo "$sel" | cut -d'|' -f1)"
        rom_path="$(echo "$sel" | cut -d'|' -f2)"
        local rom_file
        rom_file="$(basename "$rom_path")"

        "$SHOW_MESSAGE" "Delete ROM?|$rom_file" -l ab -a "YES" -b "NO"
        [ $? -ne 0 ] && continue

        delete_rom "$rom_path"
        remove_from_menu_txt "$rom_path"
        "$SHOW_MESSAGE" "Deleted|$rom_file" -t 2
    done
}

# -------------------------------------------------------------------
# Mode 2: Browse & Delete (flat list of all ROMs)
# -------------------------------------------------------------------
mode_browse_and_delete() {
    while true; do
        > "$BROWSE_MENU"
        echo "Browse & Delete|__HEADER__|header" >> "$BROWSE_MENU"

        local count=0
        for system_dir in "$ROMS_BASE"/*/; do
            local system_name
            system_name="$(basename "$system_dir")"

            # Skip special/hidden directories
            case "$system_name" in
                "to_remove (CUSTOM)"|".res"|.*) continue ;;
            esac

            for rom in "$system_dir"*; do
                [ -f "$rom" ] || continue
                local rom_file
                rom_file="$(basename "$rom")"
                # Skip hidden files
                case "$rom_file" in
                    .*) continue ;;
                esac
                echo "$rom_file [$system_name]|$rom|delete" >> "$BROWSE_MENU"
                count=$((count + 1))
            done
        done

        if [ "$count" -eq 0 ]; then
            "$SHOW_MESSAGE" "Browse & Delete|No ROMs found." -l a
            return
        fi

        local sel st
        sel="$("$PICKER" "$BROWSE_MENU" -a "DELETE" -b "BACK")"
        st=$?

        [ $st -eq 1 ] || [ -z "$sel" ] && return

        local action
        action="$(echo "$sel" | cut -d'|' -f3)"
        [ "$action" = "header" ] && continue

        local rom_path rom_file
        rom_path="$(echo "$sel" | cut -d'|' -f2)"
        rom_file="$(basename "$rom_path")"

        "$SHOW_MESSAGE" "Delete ROM?|$rom_file" -l ab -a "YES" -b "NO"
        [ $? -ne 0 ] && continue

        delete_rom "$rom_path"
        remove_from_menu_txt "$rom_path"
        "$SHOW_MESSAGE" "Deleted|$rom_file" -t 2
    done
}

# -------------------------------------------------------------------
# Main menu
# -------------------------------------------------------------------
while true; do
    > "$MAIN_MENU"
    echo "Rom Manager|__HEADER__|header" >> "$MAIN_MENU"
    echo "Delete from List|list|action" >> "$MAIN_MENU"
    echo "Browse & Delete|browse|action" >> "$MAIN_MENU"

    SEL="$("$PICKER" "$MAIN_MENU" -a "SELECT" -b "EXIT")"
    ST=$?

    [ $ST -eq 1 ] || [ -z "$SEL" ] && exit 0

    ACT="$(echo "$SEL" | cut -d'|' -f2)"
    case "$ACT" in
        header) ;;
        list)   mode_delete_from_list ;;
        browse) mode_browse_and_delete ;;
    esac
done
