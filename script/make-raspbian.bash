#!/bin/bash
#
#  Copyright (c) 2021, The OpenThread Authors.
#  All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions are met:
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in the
#     documentation and/or other materials provided with the distribution.
#  3. Neither the name of the copyright holder nor the
#     names of its contributors may be used to endorse or promote products
#     derived from this software without specific prior written permission.
#
#  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
#  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
#  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
#  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
#  LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
#  CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
#  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
#  INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
#  CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
#  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
#  POSSIBILITY OF SUCH DAMAGE.
#

set -euxo pipefail

if [[ -n ${BASH_SOURCE[0]} ]]; then
    script_path="${BASH_SOURCE[0]}"
else
    script_path="$0"
fi

script_dir="$(dirname "$(realpath "$script_path")")"
OT_REFERENCE_RELEASE="$(dirname "$script_dir")"

echo "REFERENCE_RELEASE_TYPE=${REFERENCE_RELEASE_TYPE?}"
echo "IN_CHINA=${IN_CHINA:=0}"
echo "OUTPUT_ROOT=${OUTPUT_ROOT?}"
echo "OTBR_RCP_BUS=${OTBR_RCP_BUS:=UART}"
echo "REFERENCE_PLATFORM=${REFERENCE_PLATFORM?}"
echo "OTBR_RADIO_URL=${OTBR_RADIO_URL:=spinel+hdlc+uart:///dev/ttyACM0}"

if [ "$REFERENCE_RELEASE_TYPE" != "1.2" ] && [ "$REFERENCE_RELEASE_TYPE" != "1.3" ] && [ "$REFERENCE_RELEASE_TYPE" != "1.4" ]; then
    echo "Invalid reference release type: $REFERENCE_RELEASE_TYPE"
    exit 1
fi

STAGE_DIR=/tmp/raspbian
QEMU_ROOT=${OT_REFERENCE_RELEASE}/mnt-rpi
IMAGES_DIR="${IMAGES_DIR-"${HOME}/.cache/tools/images"}"
STAGING_IMAGE_FILE=""

detach_loop_devices()
{
    local image_file
    local loop_devs
    local loop_dev
    local i

    if [[ -z ${1:-} ]]; then
        return 0
    fi

    image_file=$(realpath -m "$1" 2>/dev/null || echo "$1")

    for ((i = 0; i < 30; i++)); do
        loop_devs=$(sudo losetup -j "$image_file" 2>/dev/null | cut -d: -f1 || true)
        if [[ -z $loop_devs ]]; then
            return 0
        fi

        while IFS= read -r loop_dev; do
            if [[ -n $loop_dev ]]; then
                sudo losetup -d "$loop_dev" 2>/dev/null || true
            fi
        done <<<"$loop_devs"

        if command -v udevadm >/dev/null 2>&1; then
            sudo udevadm settle 2>/dev/null || true
        fi

        loop_devs=$(sudo losetup -j "$image_file" 2>/dev/null | cut -d: -f1 || true)
        if [[ -z $loop_devs ]]; then
            return 0
        fi

        sleep 0.5
    done

    echo "ERROR: Timed out waiting for loop devices to detach for $image_file: $loop_devs" >&2
    return 1
}

kill_mount_processes()
{
    local target_dir="${1:-}"
    local resolved_dir
    local pid

    if [[ -z $target_dir ]]; then
        return 1
    fi

    resolved_dir=$(realpath -m "$target_dir" 2>/dev/null || true)
    if [[ -z $resolved_dir ]] || [[ $resolved_dir == "/" ]]; then
        return 1
    fi

    while IFS= read -r pid; do
        if [[ $pid =~ ^[0-9]+$ ]] && [[ $pid -ne $$ ]] && [[ $pid -ne $PPID ]]; then
            sudo kill -9 "$pid" 2>/dev/null || true
        fi
    done < <(sudo lsof -t "$resolved_dir" 2>/dev/null || true)
}

unmount_image()
{
    local i
    local resolved_root

    if [[ -z ${QEMU_ROOT:-} ]]; then
        echo "ERROR: QEMU_ROOT is empty" >&2
        return 1
    fi

    resolved_root=$(realpath -m "$QEMU_ROOT")
    if [[ -z $resolved_root ]] || [[ $resolved_root == "/" ]]; then
        echo "ERROR: Refusing to unmount root directory" >&2
        return 1
    fi

    if mountpoint -q "$resolved_root" 2>/dev/null; then
        sync

        kill_mount_processes "$resolved_root"

        # Teardown QEMU machine
        sudo "${OT_REFERENCE_RELEASE}"/docker-rpi-emu/scripts/qemu-cleanup.sh "$resolved_root" || true

        # Unmount
        for ((i = 0; i < 10; i++)); do
            if sudo umount -R "$resolved_root" 2>/dev/null || ! mountpoint -q "$resolved_root" 2>/dev/null; then
                break
            fi

            kill_mount_processes "$resolved_root"

            sleep 0.5
        done

        if mountpoint -q "$resolved_root" 2>/dev/null; then
            sudo umount -f -R "$resolved_root"
        fi
    fi

    detach_loop_devices "${STAGING_IMAGE_FILE:-}"
}

cleanup()
{
    set +e
    unmount_image || true
    set -e
}

trap cleanup EXIT

main()
{
    OPENTHREAD_COMMIT_HASH=$(git -C "${OT_REFERENCE_RELEASE}"/openthread rev-parse --short HEAD)
    OT_BR_POSIX_COMMIT_HASH=$(git -C "${OT_REFERENCE_RELEASE}"/ot-br-posix rev-parse --short HEAD)

    # Ensure qemu is installed
    if ! command -v /usr/bin/qemu-arm-static; then
        "${OT_REFERENCE_RELEASE}"/script/bootstrap.bash qemu
    fi

    # Ensure build dependencies are installed
    if ! (command -v unzip >/dev/null && command -v xz >/dev/null); then
        "${OT_REFERENCE_RELEASE}"/script/bootstrap.bash packages
    fi

    # Ensure OUTPUT_ROOT exists
    mkdir -p "$OUTPUT_ROOT"

    # Ensure IMAGES_DIR exists
    [ -d "$IMAGES_DIR" ] || mkdir -p "$IMAGES_DIR"

    # Download raspios image
    RASPIOS_URL=https://downloads.raspberrypi.com/raspios_lite_armhf/images/raspios_lite_armhf-2025-05-13/2025-05-13-raspios-bookworm-armhf-lite.img.xz
    IMAGE_ARCHIVE=$(basename "${RASPIOS_URL}")
    wget -q -O "$IMAGES_DIR/$IMAGE_ARCHIVE" -c "$RASPIOS_URL"

    # Extract the downloaded archive
    mime_type=$(file "$IMAGES_DIR/$IMAGE_ARCHIVE" --mime-type)
    if [[ $mime_type == *"application/zip"* ]]; then
        IMAGE_FILE=$(basename "${IMAGE_ARCHIVE}" .zip).img
        unzip -o "$IMAGES_DIR/$IMAGE_ARCHIVE" -d "$IMAGES_DIR"
    elif [[ $mime_type == *"application/x-xz"* ]]; then
        IMAGE_FILE=$(basename "${IMAGE_ARCHIVE}" .xz)
        xz -f -k -d "$IMAGES_DIR/$IMAGE_ARCHIVE" -T0
    else
        echo "ERROR: Unrecognized archive type\n${mime_type}"
        exit 3
    fi
    ls -alh $IMAGES_DIR/$IMAGE_FILE

    # Ensure STAGE_DIR exists. Create a copy of IMAGE_FILE in STAGE_DIR
    [ -d "$STAGE_DIR" ] || mkdir -p "$STAGE_DIR"

    STAGING_IMAGE_FILE="$STAGE_DIR/otbr.${REFERENCE_RELEASE_TYPE?}-$(date +%Y%m%d).ot_${OPENTHREAD_COMMIT_HASH}.ot-br_${OT_BR_POSIX_COMMIT_HASH}.img"
    export STAGING_IMAGE_FILE
    cp "$IMAGES_DIR/$IMAGE_FILE" "$STAGING_IMAGE_FILE"

    # Expand IMAGE_FILE by EXPAND_SIZE
    # unit MB
    EXPAND_SIZE=6144
    dd if=/dev/zero bs=1M count=$EXPAND_SIZE >>"$STAGING_IMAGE_FILE"
    ls -alh "$STAGING_IMAGE_FILE"
    sudo "${OT_REFERENCE_RELEASE}"/docker-rpi-emu/scripts/expand.sh "$STAGING_IMAGE_FILE" "$EXPAND_SIZE"
    detach_loop_devices "$STAGING_IMAGE_FILE"

    # Create mount dir
    mkdir -p "$QEMU_ROOT"

    # Mount .img
    "${OT_REFERENCE_RELEASE}"/script/mount.bash "$STAGING_IMAGE_FILE" "$QEMU_ROOT"

    # Mount /etc/resolv.conf
    if [ -f "/etc/resolv.conf" ]; then
        sudo mount -o ro,bind /etc/resolv.conf "$QEMU_ROOT"/etc/resolv.conf
    fi

    # Start RPi QEMU machine
    sudo "${OT_REFERENCE_RELEASE}"/docker-rpi-emu/scripts/qemu-setup.sh "$QEMU_ROOT"

    # Ensure git_archive_all is installed
    if ! python3 -m pip show git_archive_all; then
        "${OT_REFERENCE_RELEASE}"/script/bootstrap.bash python
    fi

    # Copy ot-reference-release repo into QEMU_ROOT
    python3 -m git_archive_all "$STAGE_DIR"/repo.tar.gz
    sudo mkdir -p "$QEMU_ROOT"/home/pi/repo
    sudo tar xzf "$STAGE_DIR"/repo.tar.gz --absolute-names --strip-components 1 -C "$QEMU_ROOT"/home/pi/repo

    # Run OTBR install
    sudo chroot "$QEMU_ROOT" /bin/bash -c "export DOCKER=${DOCKER-0}; /home/pi/repo/script/otbr-setup.bash ${REFERENCE_RELEASE_TYPE?} $IN_CHINA ${REFERENCE_PLATFORM?} ${OPENTHREAD_COMMIT_HASH} ${OT_BR_POSIX_COMMIT_HASH} ${OTBR_RCP_BUS} ${OTBR_RADIO_URL}"
    sudo chroot "$QEMU_ROOT" /bin/bash /home/pi/repo/script/otbr-cleanup.bash
    echo "enable_uart=1" | sudo tee -a "$QEMU_ROOT"/boot/config.txt
    echo "dtoverlay=disable-bt" | sudo tee -a "$QEMU_ROOT"/boot/config.txt
    if [[ ${OTBR_RCP_BUS} == "SPI" ]]; then
        echo "dtparam=spi=on" | sudo tee -a "$QEMU_ROOT"/boot/config.txt
    fi
    sudo touch "$QEMU_ROOT"/boot/ssh && sync && sleep 1

    # Create userconf.txt for headless setup (Bookworm requirement)
    # This pre-configures the 'pi' user with a password to bypass the first-boot wizard.
    # The password hash is produced with SHA-512 ("openssl passwd -6").
    PASSWD_HASH=$(openssl passwd -6 "${PI_PASSWORD?PI_PASSWORD environment variable is not set}")
    echo "pi:${PASSWD_HASH}" | sudo tee "$QEMU_ROOT/boot/userconf.txt" >/dev/null

    # Unmount image and detach loop devices before shrinking and archiving
    unmount_image

    # Shrink .img
    if [[ ! -f /usr/bin/pishrink.sh ]]; then
        sudo wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O /usr/bin/pishrink.sh && sudo chmod a+x /usr/bin/pishrink.sh
    fi
    set +e
    sudo /usr/bin/pishrink.sh "$STAGING_IMAGE_FILE"
    ret_val=$?
    # Ignore error when pishrink can't shrink the image any further
    if [[ $ret_val -ne 11 ]] && [[ $ret_val -ne 0 ]]; then
        exit $ret_val
    fi
    set -e
    detach_loop_devices "$STAGING_IMAGE_FILE"

    # Write .img to SD Card
    if [[ -n ${SD_CARD:=} ]]; then
        sudo sh -c "dcfldd if="$STAGING_IMAGE_FILE" of=$SD_CARD bs=1m && sync"
    fi

    # Compress .img and move archive to OUTPUT_ROOT
    IMG_ZIP_FILE="$(basename "$STAGING_IMAGE_FILE").zip"
    zip -j "$OUTPUT_ROOT/$IMG_ZIP_FILE" "$STAGING_IMAGE_FILE"
}

main "$@"
