#!/bin/bash
echo "Welcome to amsh shell!"
while true; do
    echo -n "amsh> "
    read command
    if [ "$command" = "exit" ]; then
        echo "Exiting amsh..."
        break
    fi
    sh -c "$command"
done