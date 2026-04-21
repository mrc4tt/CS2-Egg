#!/bin/bash
source /utils/logging.sh
source /utils/version.sh

# Directories
GAME_DIRECTORY="./game/csgo"
OUTPUT_DIR="./game/csgo/addons"
TEMP_DIR="./temps"
VERSION_FILE="${EGG_DIR:-/home/container/egg}/versions.txt"

# ─── Semver Comparison ──────────────────────────────────────────────
# Returns: 0 = equal, 1 = v1 > v2, 2 = v1 < v2
semver_compare() {
    local v1=$(echo "$1" | sed 's/^[vV]//')
    local v2=$(echo "$2" | sed 's/^[vV]//')

    if [ "$v1" = "$v2" ]; then
        return 0
    fi

    # Use sort -V to find the "largest" version
    local highest=$(printf "%s\n%s" "$v1" "$v2" | sort -V | tail -n1)

    if [ "$v1" = "$highest" ]; then
        return 1 # v1 > v2
    else
        return 2 # v1 < v2
    fi
}

# ─── Version Tracking ───────────────────────────────────────────────
get_current_version() {
    local addon="$1"
    if [ -f "$VERSION_FILE" ]; then
        grep "^$addon=" "$VERSION_FILE" | cut -d'=' -f2
    else
        echo ""
    fi
}

update_version_file() {
    local addon="$1"
    local new_version="$2"

    mkdir -p "$(dirname "$VERSION_FILE")"

    if [ -f "$VERSION_FILE" ] && grep -q "^$addon=" "$VERSION_FILE"; then
        sed -i "s/^$addon=.*/$addon=$new_version/" "$VERSION_FILE"
    else
        echo "$addon=$new_version" >> "$VERSION_FILE"
    fi
}

# ─── Download & Extract ─────────────────────────────────────────────
handle_download_and_extract() {
    local url="$1"
    local output_file="$2"
    local extract_dir="$3"
    local file_type="$4"  # "zip" or "tar.gz"

    log_message "Downloading from: $url" "debug"

    local max_retries=3
    local retry=0
    while [ $retry -lt $max_retries ]; do
        if curl -fsSL -m 300 -o "$output_file" "$url"; then
            break
        fi
        ((retry++))
        log_message "Download attempt $retry failed, retrying..." "error"
        sleep 5
    done

    if [ $retry -eq $max_retries ]; then
        log_message "Failed to download after $max_retries attempts" "error"
        return 1
    fi

    if [ ! -s "$output_file" ]; then
        log_message "Downloaded file is empty" "error"
        return 1
    fi

    log_message "Extracting to $extract_dir" "debug"
    mkdir -p "$extract_dir"

    case $file_type in
        "zip")
            unzip -qq -o "$output_file" -d "$extract_dir" || {
                log_message "Failed to extract zip file" "error"
                return 1
            }
            ;;
        "tar.gz")
            tar -xzf "$output_file" -C "$extract_dir" || {
                log_message "Failed to extract tar.gz file" "error"
                return 1
            }
            ;;
    esac

    return 0
}

# ─── Version Check (with semver) ────────────────────────────────────
check_version() {
    local addon="$1"
    local current="${2:-none}"
    local new="$3"

    if [ "$current" = "none" ] || [ -z "$current" ]; then
        log_message "New version of $addon available: $new (current: none)" "running"
        return 0 # New install
    fi

    semver_compare "$new" "$current"
    case $? in
        0) # Equal
            log_message "No new version of $addon available. Current: $current" "debug"
            return 1
            ;;
        1) # new > current
            log_message "New version of $addon available: $new (current: $current)" "running"
            return 0
            ;;
        2) # new < current → prevent downgrade
            log_message "$addon is at a newer version ($current) than latest ($new). Skipping downgrade." "info"
            return 1
            ;;
    esac
}

# ─── Addon Updaters ─────────────────────────────────────────────────
# NOTE: gameinfo.gi management (MetaMod injection, load order) is handled
# by the host-level cs2_update.sh script, not the egg.
cleanup_and_update() {
    if [ "${CLEANUP_ENABLED:-0}" = "1" ]; then
        cleanup
    fi

    mkdir -p "$TEMP_DIR"

    if [ "${METAMOD_AUTOUPDATE:-0}" = "1" ] || ([ ! -d "$OUTPUT_DIR/metamod" ] && [ "${CSS_AUTOUPDATE:-0}" = "1" ]); then
        update_metamod
    fi

    if [ "${CSS_AUTOUPDATE:-0}" = "1" ]; then
        update_addon "mrc4tt/CounterStrikeSharp" "$OUTPUT_DIR" "css" "CSS"
    fi

    # Source2ZE addons
    if [ "${SOURCE2ZE_ADDONS:-0}" = "1" ]; then
        update_source2ze_addon "Source2ZE/ServerListPlayersFix" "$OUTPUT_DIR" "serverlistplayersfix" "ServerListPlayersFix"
    fi

    # MultiAddonManager
    if [ "${MAM_AUTOUPDATE:-0}" = "1" ]; then
        update_source2ze_addon "Source2ZE/MultiAddonManager" "$OUTPUT_DIR" "mam" "MultiAddonManager"
    fi

    # Clean up
    rm -rf "$TEMP_DIR"
}

update_addon() {
    local repo="$1"
    local output_path="$2"
    local temp_subdir="$3"
    local addon_name="$4"
    local temp_dir="$TEMP_DIR/$temp_subdir"

    mkdir -p "$output_path" "$temp_dir"
    rm -rf "$temp_dir"/*

    local api_response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
    if [ -z "$api_response" ]; then
        log_message "Failed to get release info for $repo" "error"
        return 1
    fi

    local new_version=$(echo "$api_response" | grep -oP '"tag_name": "\K[^"]+')
    local current_version=$(get_current_version "$addon_name")
    local asset_url=$(echo "$api_response" | grep -oP '"browser_download_url": "\K[^"]*-with-runtime-linux-[^"]+\.zip')

    if ! check_version "$addon_name" "$current_version" "$new_version"; then
        return 0
    fi

    if [ -z "$asset_url" ]; then
        log_message "No suitable asset found for $repo" "error"
        return 1
    fi

    if handle_download_and_extract "$asset_url" "$temp_dir/download.zip" "$temp_dir" "zip"; then
        cp -r "$temp_dir/addons/." "$output_path" && \
        update_version_file "$addon_name" "$new_version" && \
        log_message "Update of $repo completed successfully" "success"
        return 0
    fi

    return 1
}

update_source2ze_addon() {
    local repo="$1"
    local output_path="$2"
    local temp_subdir="$3"
    local addon_name="$4"
    local temp_dir="$TEMP_DIR/$temp_subdir"

    mkdir -p "$output_path" "$temp_dir"
    rm -rf "$temp_dir"/*

    local api_response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
    if [ -z "$api_response" ]; then
        log_message "Failed to get release info for $repo" "error"
        return 1
    fi

    local new_version=$(echo "$api_response" | grep -oP '"tag_name": "\K[^"]+')
    local current_version=$(get_current_version "$addon_name")

    local asset_url=$(echo "$api_response" | grep -oP '"browser_download_url": "\K[^"]+' | \
        grep "releases/download" | \
        grep -v "windows" | \
        grep -E "\.(zip|tar\.gz)$" | \
        head -1)

    local file_type="zip"
    local file_ext="download.zip"
    if [[ "$asset_url" == *.tar.gz ]]; then
        file_type="tar.gz"
        file_ext="download.tar.gz"
    fi

    if ! check_version "$addon_name" "$current_version" "$new_version"; then
        return 0
    fi

    if [ -z "$asset_url" ]; then
        log_message "No suitable asset found for $repo" "error"
        return 1
    fi

    if handle_download_and_extract "$asset_url" "$temp_dir/$file_ext" "$temp_dir" "$file_type"; then
        cp -r "$temp_dir/addons/." "$output_path" && \
        update_version_file "$addon_name" "$new_version" && \
        log_message "Update of $repo completed successfully" "success"
        return 0
    fi

    return 1
}

update_metamod() {
    if [ ! -d "$OUTPUT_DIR/metamod" ]; then
        log_message "Metamod not installed. Installing Metamod..." "running"
    fi

    # 2.0 builds are published as GitHub pre-releases, so /releases/latest
    # returns the 1.12 Source 1 branch. Scan recent releases and pick the
    # newest 2.x Linux asset.
    local api_response=$(curl -s "https://api.github.com/repos/alliedmodders/metamod-source/releases?per_page=30")
    if [ -z "$api_response" ]; then
        log_message "Failed to get release info for alliedmodders/metamod-source" "error"
        return 1
    fi

    local full_url=$(echo "$api_response" | grep -oP '"browser_download_url":\s*"\K[^"]*mmsource-2\.[0-9.]+-git\d+-linux\.tar\.gz' | head -1)
    if [ -z "$full_url" ]; then
        log_message "Failed to fetch the Metamod version" "error"
        return 1
    fi

    local metamod_version=$(basename "$full_url")
    local new_version=$(echo "$metamod_version" | grep -oP 'git\d+')
    local current_version=$(get_current_version "Metamod")

    if ! check_version "Metamod" "$current_version" "$new_version"; then
        return 0
    fi

    if handle_download_and_extract "$full_url" "$TEMP_DIR/metamod.tar.gz" "$TEMP_DIR/metamod" "tar.gz"; then
        cp -rf "$TEMP_DIR/metamod/addons/." "$OUTPUT_DIR/" && \
        update_version_file "Metamod" "$new_version" && \
        log_message "Metamod update completed successfully" "success"
        return 0
    fi

    return 1
}
