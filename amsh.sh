#!/bin/bash

echo "Welcome to amsh shell!"

# Custom cd command
custom_cd() {
    local target_dir="$1"

    # Check if the directory exists
    if [ ! -d "$target_dir" ]; then
        echo "Directory not found: $target_dir"
        return 1
    fi

    # Check if the target directory passes through a mountpoint
    while read -r mountpoint device filesystem options; do
        if [[ "$target_dir" == "$mountpoint"* ]]; then

            # Cehck if the mountpoint is already mounted
            if ! mount | grep -q "$mountpoint"; then
                echo "Mounting $mountpoint..."
                sudo mount "$device" "$mountpoint"
                if [ $? -ne 0 ]; then
                    echo "Failed to mount $mountpoint"
                    return 1
                fi
            fi

        fi
    done <config/fstab_similar

    # Change the directory
    cd "$target_dir" || return 1
    echo "Changed directory to $target_dir"
}

is_mounted() {
    local target_dir="$1"
    if findmnt "$target_dir" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

auto_mount() {
    local target_dir="$1"

    # Detect if `target_dir` is a valid mountpoint
    if [ ! -d "$target_dir" ]; then
        echo "Directory not found: $target_dir"
        return 1
    fi

    # Check if the target is already mounted
    if is_mounted "$target_dir"; then
        echo "$target_dir is already mounted."
        return 0
    fi

    # Try to mount the device
    echo "Attempting to mount $target_dir..."
    sudo mount "$target_dir"
    if [ $? -eq 0 ]; then
        echo "Mounted $target_dir successfully."
        return 0
    else
        echo "Failed to mount $target_dir."
        return 1
    fi
}

while true; do
    echo -n "amsh> "
    read command
    if [ "$command" = "exit" ]; then
        echo "Exiting amsh..."
        break
    fi
    sh -c "$command"
done
