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

while true; do
    echo -n "amsh> "
    read command
    if [ "$command" = "exit" ]; then
        echo "Exiting amsh..."
        break
    fi
    sh -c "$command"
done
