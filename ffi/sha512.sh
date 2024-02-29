#!/bin/bash

# Check if argument is provided
if [ -z "$1" ]
then
    echo "No argument supplied. Please provide a string to hash."
    exit 1
fi

# Compute and print the SHA512 hash
echo -n "$1" | sha512sum | awk '{ print $1 }'
