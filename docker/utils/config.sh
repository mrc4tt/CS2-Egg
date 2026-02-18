#!/bin/bash

source /utils/logging.sh

# Current config version - bump this when changing default fields
CONFIG_VERSION="1.0.0"

# Use organized egg directory structure
CONFIG_DIR="${EGG_CONFIGS_DIR:-/home/container/egg/configs}"

# Check if any config needs migration
check_config_versions() {
    local needs_migration=false
    local old_version=""

    for config_file in "$CONFIG_DIR/console-filter.json" "$CONFIG_DIR/cleanup.json" "$CONFIG_DIR/logging.json"; do
        if [ -f "$config_file" ]; then
            local current_version=$(jq -r '.version // "0.0.0"' "$config_file" 2>/dev/null)
            if [ "$current_version" != "$CONFIG_VERSION" ]; then
                needs_migration=true
                old_version="$current_version"
                break
            fi
        fi
    done

    if [ "$needs_migration" = true ]; then
        log_message "Migrating configs from v$old_version to v$CONFIG_VERSION" "info"
    fi
}

# Migrate old config to new version, returns old values for merging
migrate_config() {
    local config_file="$1"
    local config_name="$2"

    if [ ! -f "$config_file" ]; then
        return 0
    fi

    local current_version=$(jq -r '.version // "0.0.0"' "$config_file" 2>/dev/null)

    if [ "$current_version" == "$CONFIG_VERSION" ]; then
        return 0
    fi

    # Extract old values (strip metadata)
    local old_values=$(jq -r 'del(._description) | del(.version)' "$config_file" 2>/dev/null)

    # Remove old config so it gets recreated with new template
    rm "$config_file"

    echo "$old_values"
}

# Smart merge: preserves user customizations, adds new fields from template
apply_smart_merge() {
    local config_file="$1"
    local old_values="$2"

    if [ -z "$old_values" ] || [ "$old_values" = "null" ]; then
        return 0
    fi

    log_message "Merging previous settings..." "debug"
    local temp_file="${config_file}.tmp"

    jq --argjson old "$old_values" '
        def smart_merge($old):
            . as $new |
            if ($new | type) == "object" then
                $new | to_entries | map(
                    .key as $k |
                    if ($new[$k] | type) == "object" then
                        {key: $k, value: ($new[$k] | smart_merge($old[$k] // {}))}
                    else
                        {key: $k, value: ($old[$k] // $new[$k])}
                    end
                ) | from_entries
            else
                $old // $new
            end;
        smart_merge($old) | .version = "'"$CONFIG_VERSION"'"
    ' "$config_file" > "$temp_file"

    mv "$temp_file" "$config_file"
}

init_configs() {
    init_egg_directories

    mkdir -p "$CONFIG_DIR"

    # Check if migration is needed (logs once if yes)
    check_config_versions

    create_console_filter_config
    create_cleanup_config
    create_logging_config
}

create_console_filter_config() {
    local config_file="$CONFIG_DIR/console-filter.json"
    local old_values=""

    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "console-filter")
    fi

    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
{
  "version": "$CONFIG_VERSION",
  "_description": [
    "Console Filter Configuration",
    "",
    "Filter unwanted console messages from CS2 server output.",
    "",
    "Settings:",
    "  - preview_mode: Show blocked messages in debug log (true/false)",
    "  - patterns: Array of filter patterns",
    "",
    "Pattern Matching:",
    "  - Prefix with @ for exact match: \"@Server is hibernating\"",
    "  - Without @ for contains match: \"edicts used\"",
    "",
    "Note: STEAM_ACC token is automatically masked if set.",
    "",
    "Enable this feature by setting ENABLE_FILTER=1 in the Pterodactyl egg.",
    "",
    "Config location: /home/container/egg/configs/console-filter.json"
  ],
  "preview_mode": false,
  "patterns": [
    "Certificate expires"
  ]
}
EOF
        apply_smart_merge "$config_file" "$old_values"
    fi
}

create_cleanup_config() {
    local config_file="$CONFIG_DIR/cleanup.json"
    local old_values=""

    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "cleanup")
    fi

    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
{
  "version": "$CONFIG_VERSION",
  "_description": [
    "Cleanup Configuration",
    "",
    "Automatic cleanup of old logs, demos, backup files, and core dumps.",
    "",
    "Intervals (hours):",
    "  - backup_rounds_hours: Delete backup_round*.txt older than X hours (default: 24)",
    "  - demos_hours: Delete *.dem files older than X hours (default: 336 = 14 days)",
    "  - css_logs_hours: Delete CounterStrikeSharp logs older than X hours (default: 72)",
    "  - accelerator_dumps_hours: Delete Accelerator crash dumps older than X hours (default: 168)",
    "",
    "Core dumps are always cleaned on startup (they can be ~2.2GB each).",
    "",
    "Enable this feature by setting CLEANUP_ENABLED=1 in the Pterodactyl egg.",
    "",
    "Config location: /home/container/egg/configs/cleanup.json"
  ],
  "intervals": {
    "backup_rounds_hours": 24,
    "demos_hours": 336,
    "css_logs_hours": 72,
    "accelerator_dumps_hours": 168
  },
  "paths": {
    "game_directory": "./game/csgo",
    "accelerator_dumps": "./game/csgo/addons/AcceleratorCS2/dumps"
  }
}
EOF
        apply_smart_merge "$config_file" "$old_values"
    fi
}

create_logging_config() {
    local config_file="$CONFIG_DIR/logging.json"
    local old_values=""

    if [ -f "$config_file" ]; then
        old_values=$(migrate_config "$config_file" "logging")
    fi

    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
{
  "version": "$CONFIG_VERSION",
  "_description": [
    "Logging Configuration",
    "",
    "Control console output level and file logging.",
    "",
    "Console Settings:",
    "  - logging.console_level: Minimum log level (DEBUG, INFO, WARNING, ERROR)",
    "",
    "File Logging:",
    "  - logging.file_enabled: Enable daily rotating log files (true/false)",
    "  - logging.max_size_mb: Maximum total log directory size in MB",
    "  - logging.max_files: Maximum number of log files to keep",
    "  - logging.max_days: Maximum age of log files in days",
    "",
    "Log files stored in: /home/container/egg/logs/YYYY-MM-DD.log",
    "",
    "Config location: /home/container/egg/configs/logging.json"
  ],
  "logging": {
    "console_level": "INFO",
    "file_enabled": false,
    "max_size_mb": 100,
    "max_files": 30,
    "max_days": 7
  }
}
EOF
        apply_smart_merge "$config_file" "$old_values"
    fi
}

get_config_value() {
    local config_file="$1"
    local json_path="$2"
    local default_value="$3"
    local full_path="$CONFIG_DIR/$config_file"

    if [ ! -f "$full_path" ]; then
        echo "$default_value"
        return
    fi

    local value=$(jq -r "$json_path // \"$default_value\"" "$full_path" 2>/dev/null)

    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default_value"
    else
        echo "$value"
    fi
}

load_configs() {
    # Load console filter config if enabled
    if [ "${ENABLE_FILTER:-0}" -eq 1 ]; then
        export FILTER_PREVIEW_MODE=$(get_config_value "console-filter.json" ".preview_mode" "false")
    fi

    # Load cleanup config if enabled
    if [ "${CLEANUP_ENABLED:-0}" -eq 1 ]; then
        export CLEANUP_BACKUP_HOURS=$(get_config_value "cleanup.json" ".intervals.backup_rounds_hours" "24")
        export CLEANUP_DEMOS_HOURS=$(get_config_value "cleanup.json" ".intervals.demos_hours" "168")
        export CLEANUP_LOGS_HOURS=$(get_config_value "cleanup.json" ".intervals.css_logs_hours" "72")
        export CLEANUP_DUMPS_HOURS=$(get_config_value "cleanup.json" ".intervals.accelerator_dumps_hours" "168")
        export CLEANUP_GAME_DIR=$(get_config_value "cleanup.json" ".paths.game_directory" "./game/csgo")
        export CLEANUP_DUMPS_DIR=$(get_config_value "cleanup.json" ".paths.accelerator_dumps" "./game/csgo/addons/AcceleratorCS2/dumps")
    fi

    # Load logging config (always available)
    export CONSOLE_LOG_LEVEL=$(get_config_value "logging.json" ".logging.console_level" "INFO")
    export LOG_FILE_ENABLED=$(get_config_value "logging.json" ".logging.file_enabled" "false")
    export LOG_MAX_SIZE_MB=$(get_config_value "logging.json" ".logging.max_size_mb" "100")
    export LOG_MAX_FILES=$(get_config_value "logging.json" ".logging.max_files" "30")
    export LOG_MAX_DAYS=$(get_config_value "logging.json" ".logging.max_days" "7")
}
