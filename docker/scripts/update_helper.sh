#!/bin/bash
source /utils/logging.sh

# Legacy migration - move old files to new egg directory structure
migrate_legacy_files() {
    local egg_dir="/home/container/egg"
    local old_log="/home/container/egg.log"
    local old_version="/home/container/game/versions.txt"
    local old_mute_cfg="/home/container/game/mute_messages.cfg"

    # Only run if the egg directory doesn't exist yet
    if [ -d "$egg_dir" ]; then
        return 0
    fi

    log_message "Detected first run with new structure - checking for legacy files..." "info"

    local found_legacy=false

    # Check for old egg.log file
    if [ -f "$old_log" ]; then
        log_message "Found legacy egg.log - migrating..." "info"
        mkdir -p "${egg_dir}/logs"
        local timestamp=$(date +%Y-%m-%d)
        mv "$old_log" "${egg_dir}/logs/${timestamp}.log"
        log_message "Migrated egg.log → egg/logs/${timestamp}.log" "success"
        found_legacy=true
    fi

    # Check for old version file
    if [ -f "$old_version" ]; then
        log_message "Found legacy versions.txt - migrating..." "info"
        mkdir -p "$egg_dir"
        mv "$old_version" "${egg_dir}/versions.txt"
        log_message "Migrated game/versions.txt → egg/versions.txt" "success"
        found_legacy=true
    fi

    # Check for old mute_messages.cfg → convert to JSON console-filter
    if [ -f "$old_mute_cfg" ]; then
        log_message "Found legacy mute_messages.cfg - migrating..." "info"
        mkdir -p "${egg_dir}/configs"

        local patterns=()

        while IFS= read -r line; do
            local trimmed=$(echo "$line" | xargs)
            if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ -n "$trimmed" ]]; then
                patterns+=("$trimmed")
            fi
        done < "$old_mute_cfg"

        # Build JSON patterns array
        local json_patterns=""
        for pattern in "${patterns[@]}"; do
            if [ -z "$json_patterns" ]; then
                json_patterns="\"$pattern\""
            else
                json_patterns="${json_patterns}, \"$pattern\""
            fi
        done

        cat > "${egg_dir}/configs/console-filter.json" <<CONFIGEOF
{
  "version": "1.0.0",
  "_description": [
    "Console Filter Configuration",
    "",
    "NOTE: This config was automatically migrated from legacy mute_messages.cfg"
  ],
  "preview_mode": false,
  "patterns": [${json_patterns}]
}
CONFIGEOF

        # Backup old file
        mv "$old_mute_cfg" "${old_mute_cfg}.backup"
        log_message "Migrated mute_messages.cfg → egg/configs/console-filter.json" "success"
        found_legacy=true
    fi

    if [ "$found_legacy" = true ]; then
        log_message "Legacy file migration completed!" "success"
    fi
}
