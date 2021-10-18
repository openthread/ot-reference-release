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

IMAGE_URL=https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/2021-05-07-raspios-buster-armhf-lite.zip
echo "REFERENCE_RELEASE_TYPE=${REFERENCE_RELEASE_TYPE?}"
echo "IN_CHINA=${IN_CHINA:=0}"
echo "OUTPUT_ROOT=${OUTPUT_ROOT?}"
echo "REFERENCE_PLATFORM=${REFERENCE_PLATFORM?}"

if [ "$REFERENCE_RELEASE_TYPE" != "certification" ] && [ "$REFERENCE_RELEASE_TYPE" != "1.3" ]; then
  echo "Invalid reference release type: $REFERENCE_RELEASE_TYPE"
  exit 1
fi

BUILD_TARGET=raspbian-gcc

TOOLS_HOME=$HOME/.cache/tools

main() {
  BUILD_TARGET=$BUILD_TARGET IMAGE_URL=$IMAGE_URL ./script/bootstrap.bash

  IMAGE_NAME=$(basename "${IMAGE_URL}" .zip)
  STAGE_DIR=/tmp/raspbian
  IMAGE_DIR=/media/rpi
  IMAGE_FILE="$TOOLS_HOME"/images/"$IMAGE_NAME".img

  [ -d "$STAGE_DIR" ] || mkdir -p "$STAGE_DIR"
  cp -v "$IMAGE_FILE" "$STAGE_DIR"/raspbian.img

  python3 -m git_archive_all "$STAGE_DIR"/repo.tar.gz

  sudo mkdir -p "$IMAGE_DIR"
  sudo script/mount.bash "$STAGE_DIR"/raspbian.img "$IMAGE_DIR"

  (
    cd docker-rpi-emu/scripts
    sudo mount --bind /dev/pts "$IMAGE_DIR"/dev/pts
    sudo mkdir -p "$IMAGE_DIR"/home/pi/repo
    sudo tar xzf "$STAGE_DIR"/repo.tar.gz --strip-components 1 -C "$IMAGE_DIR"/home/pi/repo
    sudo ./qemu-setup.sh "$IMAGE_DIR"
    sudo chroot "$IMAGE_DIR" /bin/bash /home/pi/repo/script/otbr-setup.bash "${REFERENCE_RELEASE_TYPE?}" "$IN_CHINA" "${REFERENCE_PLATFORM?}"
    sudo chroot "$IMAGE_DIR" /bin/bash /home/pi/repo/script/otbr-cleanup.bash
    echo "enable_uart=1" | sudo tee -a "$IMAGE_DIR"/boot/config.txt
    echo "dtoverlay=pi3-disable-bt" | sudo tee -a "$IMAGE_DIR"/boot/config.txt
    sudo touch "$IMAGE_DIR"/boot/ssh && sync
    LOOP_NAME=$(losetup -j $STAGE_DIR/raspbian.img --output NAME -n)
    sudo sh -c "dcfldd of=$STAGE_DIR/otbr.img if=$LOOP_NAME bs=1m && sync"
    sudo cp $STAGE_DIR/otbr.img $STAGE_DIR/otbr_original.img
    if [[ ! -f /usr/bin/pishrink.sh ]]; then
      sudo wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O /usr/bin/pishrink.sh && sudo chmod a+x /usr/bin/pishrink.sh
    fi
    sudo /usr/bin/pishrink.sh $STAGE_DIR/otbr.img
    if [[ -n ${SD_CARD:=} ]]; then
      sudo sh -c "dcfldd if=$STAGE_DIR/otbr.img of=$SD_CARD bs=1m && sync"
    fi
    IMG_ZIP_FILE=otbr."$(date +%Y%m%d)".img.zip
    (cd $STAGE_DIR && zip "$IMG_ZIP_FILE" otbr.img && mv "$IMG_ZIP_FILE" "$OUTPUT_ROOT")
    sudo umount -lf "${LOOP_NAME}p1"
    sudo umount -lf "${LOOP_NAME}p2"
    sudo losetup -d "${LOOP_NAME}"
  )
}

main "$@"
