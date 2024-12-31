#!/bin/bash

echo "Welcome to amsh shell!"

# Custom cd command
custom_cd() {
    local target_dir="$1"

    # Check if the target directory exists
    if [ ! -d "$target_dir" ]; then
        echo "Directory not found: $target_dir"
        return 1
    fi

    # Try to mount if necessary
    auto_mount "$target_dir"

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
    # Show the prompt
    echo -n "amsh> "

    # Read the command and arguments
    read command args

    # Check the entered command
    case "$command" in
    cd) # For cmd `cd`
        custom_cd "$args"
        ;;
    exit) # For cmd `exit`
        echo "Exiting amsh..."
        break
        ;;
    *) # For other commands
        sh -c "$command"
        ;;
    esac
done
