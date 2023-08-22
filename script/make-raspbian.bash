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

if [ "$REFERENCE_RELEASE_TYPE" != "1.2" ] && [ "$REFERENCE_RELEASE_TYPE" != "1.3" ] && [ "$REFERENCE_RELEASE_TYPE" != "1.3.1" ]; then
    echo "Invalid reference release type: $REFERENCE_RELEASE_TYPE"
    exit 1
fi

STAGE_DIR=/tmp/raspbian
QEMU_ROOT=${OT_REFERENCE_RELEASE}/mnt-rpi
IMAGES_DIR="${IMAGES_DIR-"${HOME}/.cache/tools/images"}"

cleanup()
{
    set +e
    for pid in $(sudo lsof -t "$QEMU_ROOT"); do
        sudo kill -9 "$pid"
    done

    # Teardown QEMU machine
    sudo "${OT_REFERENCE_RELEASE}"/docker-rpi-emu/scripts/qemu-cleanup.sh "$QEMU_ROOT" || true

    # Unmount
    sudo umount -f -R "$QEMU_ROOT" || true
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

    # Ensure OUTPUT_ROOT exists
    mkdir -p "$OUTPUT_ROOT"

    # Ensure IMAGES_DIR exists
    [ -d "$IMAGES_DIR" ] || mkdir -p "$IMAGES_DIR"

    # Download raspios image
    RASPIOS_URL=https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
    IMAGE_ARCHIVE=$(basename "${RASPIOS_URL}")
    IMAGE_FILE=$(basename "${IMAGE_ARCHIVE}" .zip).img
    wget -q -O "$IMAGES_DIR/$IMAGE_ARCHIVE" -c "$RASPIOS_URL"

    # Extract the downloaded archive
    mime_type=$(file "$IMAGES_DIR/$IMAGE_ARCHIVE" --mime-type)
    if [[ $mime_type == *"application/zip"* ]]; then
        unzip -o "$IMAGES_DIR/$IMAGE_ARCHIVE" -d $IMAGES_DIR
    elif [[ $mime_type == *"application/"* ]]; then
        xz -f -k -d "$IMAGES_DIR/$IMAGE_ARCHIVE"
    else
        echo "ERROR: Unrecognized archive type\n${mime_type}"
        exit 3
    fi
    ls -alh $IMAGES_DIR/$IMAGE_FILE

    # Ensure STAGE_DIR exists. Create a copy of IMAGE_FILE in STAGE_DIR
    [ -d "$STAGE_DIR" ] || mkdir -p "$STAGE_DIR"

    export STAGING_IMAGE_FILE="$STAGE_DIR/otbr.${REFERENCE_RELEASE_TYPE?}-$(date +%Y%m%d).ot_${OPENTHREAD_COMMIT_HASH}.ot-br_${OT_BR_POSIX_COMMIT_HASH}.img"
    cp "$IMAGES_DIR/$IMAGE_FILE" "$STAGING_IMAGE_FILE"

    # Expand IMAGE_FILE by EXPAND_SIZE
    # unit MB
    EXPAND_SIZE=6144
    dd if=/dev/zero bs=1M count=$EXPAND_SIZE >>"$STAGING_IMAGE_FILE"
    ls -alh "$STAGING_IMAGE_FILE"
    sudo "${OT_REFERENCE_RELEASE}"/docker-rpi-emu/scripts/expand.sh "$STAGING_IMAGE_FILE" "$EXPAND_SIZE"

    # Create mount dir
    mkdir -p "$QEMU_ROOT"

    # Mount .img
    sudo "${OT_REFERENCE_RELEASE}"/docker-rpi-emu/scripts/mount.sh "$STAGING_IMAGE_FILE" $QEMU_ROOT

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

    # Write .img to SD Card
    if [[ -n ${SD_CARD:=} ]]; then
        sudo sh -c "dcfldd if="$STAGING_IMAGE_FILE" of=$SD_CARD bs=1m && sync"
    fi

    # Compress .img and move archive to OUTPUT_ROOT
    IMG_ZIP_FILE="$(basename "$STAGING_IMAGE_FILE").zip"
    zip -j "$OUTPUT_ROOT/$IMG_ZIP_FILE" "$STAGING_IMAGE_FILE"
}

main "$@"
