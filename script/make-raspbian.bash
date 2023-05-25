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
repo_dir="$(dirname "$script_dir")"

IMAGE_URL=https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
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

BUILD_TARGET=raspbian-gcc
STAGE_DIR=/tmp/raspbian
IMAGE_DIR=${repo_dir}/mnt-rpi
TOOLS_HOME=$HOME/.cache/tools

cleanup()
{
    set +e

    # Unmount and detach any loop devices
    loop_names=$(losetup -j $STAGE_DIR/raspbian.img --output NAME -n)
    for loop in ${loop_names}; do
        sudo umount -lf "${loop}p1"
        sudo umount -lf "${loop}p2"
        sudo losetup -d "${loop}"
    done

    set -e
}

trap cleanup EXIT

main()
{
    BUILD_TARGET=$BUILD_TARGET IMAGE_URL=$IMAGE_URL ./script/bootstrap.bash

    IMAGE_NAME=$(basename "${IMAGE_URL}" .zip)
    IMAGE_FILE="$TOOLS_HOME"/images/"$IMAGE_NAME".img

    [ -d "$STAGE_DIR" ] || mkdir -p "$STAGE_DIR"
    cp -v "$IMAGE_FILE" "$STAGE_DIR"/raspbian.img

    python3 -m git_archive_all "$STAGE_DIR"/repo.tar.gz

    mkdir -p "$IMAGE_DIR"
    chown -R "$USER": "$IMAGE_DIR"
    ls -alh "$IMAGE_DIR"
    script/mount.bash "$STAGE_DIR"/raspbian.img "$IMAGE_DIR"

    (
        OPENTHREAD_COMMIT_HASH=$(cd "${repo_dir}"/openthread && git rev-parse --short HEAD)
        OT_BR_POSIX_COMMIT_HASH=$(cd "${repo_dir}"/ot-br-posix && git rev-parse --short HEAD)
        cd docker-rpi-emu/scripts
        sudo mount --bind /dev/pts "$IMAGE_DIR"/dev/pts
        sudo mkdir -p "$IMAGE_DIR"/home/pi/repo
        sudo tar xzf "$STAGE_DIR"/repo.tar.gz --absolute-names --strip-components 1 -C "$IMAGE_DIR"/home/pi/repo
        sudo ./qemu-setup.sh "$IMAGE_DIR"
        sudo chroot "$IMAGE_DIR" /bin/bash /home/pi/repo/script/otbr-setup.bash "${REFERENCE_RELEASE_TYPE?}" "$IN_CHINA" "${REFERENCE_PLATFORM?}" "${OPENTHREAD_COMMIT_HASH}" "${OT_BR_POSIX_COMMIT_HASH}" "${OTBR_RCP_BUS}" "${OTBR_RADIO_URL}"
        sudo chroot "$IMAGE_DIR" /bin/bash /home/pi/repo/script/otbr-cleanup.bash
        echo "enable_uart=1" | sudo tee -a "$IMAGE_DIR"/boot/config.txt
        echo "dtoverlay=disable-bt" | sudo tee -a "$IMAGE_DIR"/boot/config.txt
        if [[ ${OTBR_RCP_BUS} == "SPI" ]]; then
            echo "dtparam=spi=on" | sudo tee -a "$IMAGE_DIR"/boot/config.txt
        fi
        sudo touch "$IMAGE_DIR"/boot/ssh && sync && sleep 1
        sudo ./qemu-cleanup.sh "$IMAGE_DIR"
        LOOP_NAME=$(losetup -j $STAGE_DIR/raspbian.img --output NAME -n)
        sudo sh -c "dcfldd of=$STAGE_DIR/otbr.img if=$LOOP_NAME bs=1m && sync"
        sudo cp $STAGE_DIR/otbr.img $STAGE_DIR/otbr_original.img
        if [[ ! -f /usr/bin/pishrink.sh ]]; then
            sudo wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O /usr/bin/pishrink.sh && sudo chmod a+x /usr/bin/pishrink.sh
        fi
        set +e
        sudo /usr/bin/pishrink.sh $STAGE_DIR/otbr.img
        ret_val=$?
        # Ignore error when pishrink can't shrink the image any further
        if [[ $ret_val -ne 11 ]] && [[ $ret_val -ne 0 ]]; then
            exit $ret_val
        fi
        set -e
        if [[ -n ${SD_CARD:=} ]]; then
            sudo sh -c "dcfldd if=$STAGE_DIR/otbr.img of=$SD_CARD bs=1m && sync"
        fi
        IMG_ZIP_FILE="otbr.${REFERENCE_RELEASE_TYPE?}-$(date +%Y%m%d).ot_${OPENTHREAD_COMMIT_HASH}.ot-br_${OT_BR_POSIX_COMMIT_HASH}.img.zip"
        (cd $STAGE_DIR && zip "$IMG_ZIP_FILE" otbr.img && mv "$IMG_ZIP_FILE" "$OUTPUT_ROOT")

    )
}

main "$@"
