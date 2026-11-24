#!/bin/bash

# The MIT License (MIT) Copyright (c) 2016 Ryan Kurte
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#
# Script to mount a provided raspbian image to a provided location
#

set -euxo pipefail

# Check inputs
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 IMAGE MOUNT"
    echo "IMAGE - raspberry pi .img file"
    echo "MOUNT - mount location in the file system"
    exit
fi

if [ ! -f "$1" ]; then
    echo "Image file $1 does not exist"
    exit 1
fi

if [ ! -d "$2" ]; then
    echo "Mount point $2 does not exist"
    exit 2
fi

IMAGE_FILE="$1"
MOUNT_POINT="$2"

if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
    echo "Mount point $MOUNT_POINT is already mounted" >&2
    exit 2
fi

echo "Attempting to mount $IMAGE_FILE to $MOUNT_POINT"

LOOP_BASE=""
MOUNTED=0

cleanup()
{
    if [ "$MOUNTED" -ne 1 ]; then
        set +e
        if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
            sudo umount -R "$MOUNT_POINT" 2>/dev/null || sudo umount -f -R "$MOUNT_POINT" 2>/dev/null || true
        fi
        if [ -n "$LOOP_BASE" ]; then
            sudo losetup -d "$LOOP_BASE" 2>/dev/null || true
        fi
    fi
}

trap cleanup EXIT

# Attach loopback device
LOOP_BASE=$(sudo losetup -f -P --show "$IMAGE_FILE")

echo "Attached base loopback at: $LOOP_BASE"

P1_NAME=${LOOP_BASE}p1
P2_NAME=${LOOP_BASE}p2

if command -v udevadm >/dev/null 2>&1; then
    sudo udevadm settle 2>/dev/null || true
fi

for ((i = 0; i < 20; i++)); do
    if [ -b "$P1_NAME" ] && [ -b "$P2_NAME" ]; then
        break
    fi
    sleep 0.2
done

if [ ! -b "$P1_NAME" ] || [ ! -b "$P2_NAME" ]; then
    echo "Partition devices $P1_NAME and $P2_NAME did not appear" >&2
    exit 3
fi

# Mount partitions from the attached loopback device
sudo mount "$P2_NAME" -o rw "$MOUNT_POINT"
sudo mount "$P1_NAME" -o rw "$MOUNT_POINT"/boot
MOUNTED=1

echo "Mounted to $MOUNT_POINT and $MOUNT_POINT/boot"
