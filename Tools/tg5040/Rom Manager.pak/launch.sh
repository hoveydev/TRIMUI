#!/bin/sh

SCRIPT_DIR="$(dirname "$0")"
cd "$SCRIPT_DIR"

export LD_LIBRARY_PATH="/usr/trimui/lib:$LD_LIBRARY_PATH"

PICKER="./picker"
SHOW_MESSAGE="./show_message"
KEYBOARD="./keyboard"
FONT_FILE="./minui.ttf"

ROMS_BASE="/mnt/SDCARD/Roms"
MENU_TXT="$ROMS_BASE/to_remove (CUSTOM)/menu.txt"

MAIN_MENU="/tmp/rom_manager_main.txt"
DELETE_MENU="/tmp/rom_manager_delete.txt"
SEARCH_MENU="/tmp/rom_manager_search.txt"
MENU_TMP="/tmp/rom_manager_menu_tmp.txt"

trap 'rm -f "$MAIN_MENU" "$DELETE_MENU" "$SEARCH_MENU" "$MENU_TMP"' EXIT

delete_rom() {
    rom_path="$1"
    rom_dir="$(dirname "$rom_path")"
    rom_file="$(basename "$rom_path")"
    img_path="$rom_dir/.res/$rom_file.png"

    [ -f "$rom_path" ] && rm -f "$rom_path"
    [ -f "$img_path" ] && rm -f "$img_path"
}

remove_from_menu_txt() {
    rom_path="$1"

    [ -f "$MENU_TXT" ] || return 0
    > "$MENU_TMP"
    while IFS='|' read -r name path action; do
        [ -z "$name" ] && continue
        if [ "$action" = "launch" ] && [ "$path" = "$rom_path" ]; then
            continue
        fi
        echo "$name|$path|$action" >> "$MENU_TMP"
    done < "$MENU_TXT"
    mv "$MENU_TMP" "$MENU_TXT"
}

batch_delete_to_remove() {
    total=0
    while IFS='|' read -r name path action; do
        [ -z "$name" ] && continue
        [ "$action" != "launch" ] && continue
        total=$((total + 1))
    done < "$MENU_TXT"

    if [ "$total" -eq 0 ]; then
        "$SHOW_MESSAGE" "Delete from List|No games found in to_remove." -l a "$FONT_FILE"
        return 0
    fi

    "$SHOW_MESSAGE" "Delete all to_remove games?|This will remove $total entries.|Continue?" -l ab -a "YES" -b "NO" "$FONT_FILE"
    [ $? -ne 0 ] && return 0

    deleted=0
    missing=0
    > "$MENU_TMP"
    while IFS='|' read -r name path action; do
        [ -z "$name" ] && continue
        case "$action" in
            menu_options|header|__COLLECTION__)
                echo "$name|$path|$action" >> "$MENU_TMP"
                ;;
            launch)
                if [ -f "$path" ]; then
                    delete_rom "$path"
                    deleted=$((deleted + 1))
                else
                    missing=$((missing + 1))
                fi
                ;;
            *)
                echo "$name|$path|$action" >> "$MENU_TMP"
                ;;
        esac
    done < "$MENU_TXT"
    mv "$MENU_TMP" "$MENU_TXT"

    "$SHOW_MESSAGE" "Delete Complete|Deleted: $deleted|Missing: $missing" -l a "$FONT_FILE"
}

search_and_delete() {
    while true; do
        search_term="$("$KEYBOARD" "$FONT_FILE")"
        [ $? -ne 0 ] && return 0
        [ -z "$search_term" ] && return 0

        "$SHOW_MESSAGE" "Searching for|$search_term" -t 1 "$FONT_FILE" &
        search_msg_pid=$!

        > "$SEARCH_MENU"
        echo "Search Results|__HEADER__|header" >> "$SEARCH_MENU"

        find "$ROMS_BASE" -type f ! -path "*/.res/*" ! -path "*/to_remove (CUSTOM)/*" ! -name ".*" -iname "*$search_term*" | sort | while IFS= read -r path; do
            [ -f "$path" ] || continue
            rom_file="$(basename "$path")"
            system_name="$(basename "$(dirname "$path")")"
            echo "$rom_file [$system_name]|$path|delete" >> "$SEARCH_MENU"
        done

        kill "$search_msg_pid" 2>/dev/null
        wait "$search_msg_pid" 2>/dev/null

        results=$(tail -n +2 "$SEARCH_MENU" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$results" -eq 0 ]; then
            "$SHOW_MESSAGE" "Search Results|No matches found for|$search_term" -l a "$FONT_FILE"
            continue
        fi

        selection="$("$PICKER" --font "$FONT_FILE" "$SEARCH_MENU" -a "DELETE" -b "BACK")"
        picker_status=$?
        [ $picker_status -eq 1 ] && return 0
        [ -z "$selection" ] && return 0

        action="$(echo "$selection" | cut -d'|' -f3)"
        [ "$action" = "header" ] && continue

        rom_path="$(echo "$selection" | cut -d'|' -f2)"
        rom_file="$(basename "$rom_path")"

        "$SHOW_MESSAGE" "Delete ROM?|$rom_file" -l ab -a "YES" -b "NO" "$FONT_FILE"
        [ $? -ne 0 ] && continue

        delete_rom "$rom_path"
        remove_from_menu_txt "$rom_path"
        "$SHOW_MESSAGE" "Deleted|$rom_file" -t 2 "$FONT_FILE"
    done
}

while true; do
    > "$MAIN_MENU"
    echo "Rom Manager|__HEADER__|header" >> "$MAIN_MENU"
    echo "Delete from List|delete_list|action" >> "$MAIN_MENU"
    echo "Search ROMs|search|action" >> "$MAIN_MENU"

    SEL="$("$PICKER" --font "$FONT_FILE" "$MAIN_MENU" -a "SELECT" -b "EXIT")"
    ST=$?

    [ $ST -eq 1 ] || [ -z "$SEL" ] && exit 0

    ACT="$(echo "$SEL" | cut -d'|' -f2)"
    case "$ACT" in
        header) ;;
        delete_list) batch_delete_to_remove ;;
        search) search_and_delete ;;
    esac
done
