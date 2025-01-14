#!/usr/bin/env bash

###############################################################################
# Global configuration
###############################################################################
CONFIG_FILE="./config/amsh_fstab.conf"

# Associative array to track mount times. Key = mountpoint, Value = timestamp
declare -A MOUNT_TIMES

# Associative array to store source, filesystem type, and lifetime for each mountpoint.
# Key = mountpoint, Value = "source fs_type lifetime"
declare -A MOUNT_INFO

###############################################################################
# Read the configuration file and populate MOUNT_INFO
###############################################################################
/bin/grep -v '^[[:space:]]*#' "$CONFIG_FILE" 2>/dev/null | while read -r line; do
    # Ignore empty lines
    [[ -z "$line" ]] && continue

    src_fs=$(echo "$line" | awk '{print $1}')
    mp=$(echo "$line" | awk '{print $2}')
    fs_type=$(echo "$line" | awk '{print $3}')
    lifetime=$(echo "$line" | awk '{print $4}')

    MOUNT_INFO["$mp"]="$src_fs $fs_type $lifetime"
done

###############################################################################
# Helper function: Detect if a path "goes through" a configured mountpoint.
# If it does, return that mountpoint. Otherwise, return nothing.
###############################################################################
function detect_mountpoint_in_path() {
    local path="$1"

    # Convert relative paths to absolute paths using $PWD
    if [[ "$path" != /* ]]; then
        path="$PWD/$path"
    fi

    # Sort the mountpoints in descending order by length
    # so that we match the longest possible mountpoint first.
    local mp
    for mp in "${!MOUNT_INFO[@]}"; do
        # Check if the path is exactly "mp" or starts with "mp/"
        if [[ "$path" == "$mp" || "$path" == "$mp/"* ]]; then
            echo "$mp"
            return 0
        fi
    done

    return 1
}

###############################################################################
# Helper function: Check if a given mountpoint is already mounted.
###############################################################################
function is_mounted() {
    local mp="$1"
    mount | grep -q " on $mp "
}

###############################################################################
# Mount a mountpoint if it is not already mounted.
# Update the timestamp in the MOUNT_TIMES array.
###############################################################################
function ensure_mounted() {
    local mp="$1"
    local info="${MOUNT_INFO["$mp"]}"
    local src_fs=$(echo "$info" | awk '{print $1}')
    local fs_type=$(echo "$info" | awk '{print $2}')
    local lifetime=$(echo "$info" | awk '{print $3}')

    if ! is_mounted "$mp"; then
        echo "[amsh] Mounting $mp (FS: $fs_type, Source: $src_fs)"

        # Example: if fs_type is sshfs, we call sshfs; otherwise, fallback to generic mount
        if [[ "$fs_type" == "sshfs" ]]; then
            # We assume sshfs is installed. If "src_fs" is something like "sshfs://user@host:/data",
            # we might remove the "sshfs://" scheme:
            sshfs "${src_fs#sshfs://}" "$mp" || return 1
        else
            # Generic mount (could be nfs, ext4, etc.)
            sudo mount -t "$fs_type" "$src_fs" "$mp" || return 1
        fi
    fi

    # Update the timestamp
    MOUNT_TIMES["$mp"]=$(date +%s)
}

###############################################################################
# Check if a mountpoint is in use (processes have files open in it).
# We use lsof +D <mountpoint> for this purpose.
###############################################################################
function mountpoint_in_use() {
    local mp="$1"
    lsof +D "$mp" &>/dev/null
    if [[ $? -eq 0 ]]; then
        return 0  # It is in use
    else
        return 1  # Not in use
    fi
}

###############################################################################
# After each command, we check all mountpoints to see if their lifetime has expired.
# If expired and not in use, we umount.
###############################################################################
function check_unmounts() {
    local current_time=$(date +%s)

    for mp in "${!MOUNT_INFO[@]}"; do
        if is_mounted "$mp"; then
            local info="${MOUNT_INFO["$mp"]}"
            local lifetime=$(echo "$info" | awk '{print $3}')
            local mount_time="${MOUNT_TIMES["$mp"]}"

            # Check if lifetime is exceeded
            if (( current_time - mount_time > lifetime )); then
                # Check if mountpoint is still in use
                if ! mountpoint_in_use "$mp"; then
                    echo "[amsh] Unmounting $mp (lifetime expired, not in use)"
                    sudo umount "$mp"
                fi
            fi
        fi
    done
}

###############################################################################
# Internal "cd" function for amsh: parse the path, mount if necessary,
# then do a normal cd.
###############################################################################
function amsh_cd() {
    local dest="$1"

    # If no argument is given, cd to $HOME
    if [[ -z "$dest" ]]; then
        dest="$HOME"
    fi

    # Detect a mountpoint in the path
    local mp
    mp=$(detect_mountpoint_in_path "$dest")
    if [[ -n "$mp" ]]; then
        # Make sure it is mounted
        ensure_mounted "$mp"
        if [[ $? -ne 0 ]]; then
            echo "[amsh] Error mounting $mp"
            return 1
        fi
    fi

    # Perform normal cd
    builtin cd "$dest" || return 1

    # Update timestamp if a mountpoint was involved
    if [[ -n "$mp" ]]; then
        MOUNT_TIMES["$mp"]=$(date +%s)
    fi
}

###############################################################################
# Execute an external command:
# - We look for arguments that may be paths.
# - If a path involves a mountpoint, we ensure it is mounted.
# - Then we run the command with `sh -c`.
###############################################################################
function amsh_exec() {
    local cmd=("$@")

    # Heuristic to detect potential paths among arguments
    for arg in "${cmd[@]}"; do
        if [[ "$arg" == */* ]]; then
            local mp
            mp=$(detect_mountpoint_in_path "$arg")
            if [[ -n "$mp" ]]; then
                ensure_mounted "$mp"
                if [[ $? -ne 0 ]]; then
                    echo "[amsh] Error mounting $mp"
                    return 1
                fi
                # Update timestamp
                MOUNT_TIMES["$mp"]=$(date +%s)
            fi
        fi
    done

    # Join the cmd array into a single string for `sh -c`
    local joined_cmd
    joined_cmd="$(printf " %q" "${cmd[@]}")"

    # Execute via sh -c
    /bin/sh -c "${joined_cmd}"
}

###############################################################################
# Main loop: show prompt, read user commands, execute them
###############################################################################
function main_loop() {
    while true; do
        echo -n "amsh> "
        IFS= read -r line

        # If EOF or Ctrl+D was pressed:
        if [[ $? -eq 1 ]]; then
            echo
            break
        fi

        # Split the line into tokens (very simplistic splitting)
        local tokens=($line)
        [[ ${#tokens[@]} -eq 0 ]] && continue  # empty line

        local cmd="${tokens[0]}"

        case "$cmd" in
            exit)
                break
                ;;
            cd)
                amsh_cd "${tokens[1]}"
                ;;
            *)
                amsh_exec "${tokens[@]}"
                ;;
        esac

        # After each command, check if we need to unmount anything
        check_unmounts
    done
}

###############################################################################
# Start the shell
###############################################################################
main_loop
exit 0