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

set -e
set -x


IMAGE_URL=https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-01-12/2021-01-11-raspios-buster-armhf-lite.zip
echo "IMAGE_URL=${IMAGE_URL?}"
echo "IN_CHINA=$IN_CHINA"
echo "OUTPUT_DIR=${OUTPUT_DIR?}"

BUILD_TARGET=raspbian-gcc
BUILD_OPTIONS='REFERENCE_DEVICE=1 '
BUILD_OPTIONS+='BACKBONE_ROUTER=1 '
BUILD_OPTIONS+='BORDER_ROUTING=0 '
BUILD_OPTIONS+='NETWORK_MANAGER=0 '
BUILD_OPTIONS+='NAT64=0 '
BUILD_OPTIONS+='DNS64=0 '
BUILD_OPTIONS+='DHCPV6_PD=0 '
BUILD_OPTIONS+='WEB_GUI=0 '
BUILD_OPTIONS+='REST=0 '
BUILD_OPTIONS+='OTBR_OPTIONS="-DOTBR_DUA_ROUTING=ON -DOT_DUA=ON -DOT_MLR=ON" '

TOOLS_HOME=$HOME/.cache/tools

main() {
  BUILD_TARGET=$BUILD_TARGET IMAGE_URL=$IMAGE_URL sh ot-br-posix/tests/scripts/bootstrap.sh

  IMAGE_NAME=$(basename "${IMAGE_URL}" .zip)
  STAGE_DIR=/tmp/raspbian
  IMAGE_DIR=/media/rpi
  IMAGE_FILE="$TOOLS_HOME"/images/"$IMAGE_NAME".img

  [ -d "$STAGE_DIR" ] || mkdir -p "$STAGE_DIR"
  cp -v "$IMAGE_FILE" "$STAGE_DIR"/raspbian.img

  python3 -m git_archive_all "$STAGE_DIR"/repo.tar.gz

  cat >"$STAGE_DIR"/setup.sh <<EOF
#!/bin/sh
set -ex

echo "NEW VERSION"

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=\$PATH:/usr/local/bin

configure_apt_source() {
  if [ $IN_CHINA = 1 ]; then
    echo 'deb http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ buster main non-free contrib rpi
deb-src http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ buster main non-free contrib rpi' | sudo tee /etc/apt/sources.list
    echo 'deb http://mirrors.tuna.tsinghua.edu.cn/raspberrypi/ buster main ui' | sudo tee /etc/apt/sources.list.d/raspi.list
  fi
}
configure_apt_source

echo "127.0.0.1 \$(hostname)" >> /etc/hosts
chown -R pi:pi /home/pi/repo
cd /home/pi/repo/ot-br-posix
apt-get update
apt-get install -y --no-install-recommends git python3-pip
apt-get install -y --no-install-recommends nodejs npm
su -c 'RELEASE=1 $BUILD_OPTIONS script/bootstrap' pi

# Pin CMake version to 3.10.3 for issue https://github.com/openthread/ot-br-posix/issues/728.
# For more background, see https://gitlab.kitware.com/cmake/cmake/-/issues/20568.
apt-get purge -y cmake
pip3 install scikit-build
pip3 install cmake==3.10.3
cmake --version

su -c 'RELEASE=1 $BUILD_OPTIONS script/setup' pi || true

cd /home/pi/repo/
./script/make-commissioner.bash

sync
EOF

  cat >"$STAGE_DIR"/cleanup.sh <<EOF
#!/bin/sh
set -e
set -x

OTBR_BUILD_DEPS='apt-utils build-essential psmisc ninja-build cmake wget ca-certificates
  libreadline-dev libncurses-dev libdbus-1-dev libavahi-common-dev
  libavahi-client-dev libboost-dev libboost-filesystem-dev libboost-system-dev libjsoncpp-dev
  libnetfilter-queue-dev'
OTBR_DOCKER_DEPS='git ca-certificates'

cd /home/pi/repo/ot-br-posix
mv ./script /tmp
mv ./etc /tmp
find . -delete
rm -rf /usr/include
mv /tmp/script .
mv /tmp/etc .
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $OTBR_DOCKER_DEPS
apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false $OTBR_BUILD_DEPS
rm -rf /var/lib/apt/lists/*
sync
EOF

sudo mkdir -p "$IMAGE_DIR"
sudo script/mount.bash "$STAGE_DIR"/raspbian.img "$IMAGE_DIR"

  (
      cd docker-rpi-emu/scripts
      sudo mount --bind /dev/pts "$IMAGE_DIR"/dev/pts
      sudo mkdir -p "$IMAGE_DIR"/home/pi/repo
      sudo tar xzf "$STAGE_DIR"/repo.tar.gz --strip-components 1 -C "$IMAGE_DIR"/home/pi/repo
      sudo cp -v "$STAGE_DIR"/setup.sh "$IMAGE_DIR"/home/pi/setup.sh
      sudo cp -v "$STAGE_DIR"/cleanup.sh "$IMAGE_DIR"/home/pi/cleanup.sh
      sudo ./qemu-setup.sh "$IMAGE_DIR"
      sudo chroot "$IMAGE_DIR" /bin/bash /home/pi/setup.sh || true
      sudo chroot "$IMAGE_DIR" /bin/bash /home/pi/cleanup.sh
      sudo touch "$IMAGE_DIR"/boot/ssh && sync
      LOOP_NAME=$(losetup -j $STAGE_DIR/raspbian.img  --output NAME -n)
      sudo sh -c "dcfldd of=$STAGE_DIR/otbr.img if=$LOOP_NAME bs=1m && sync"
      sudo cp $STAGE_DIR/otbr.img $STAGE_DIR/otbr_original.img
      if [[ ! -f /usr/bin/pishrink.sh ]]; then
        sudo wget https://raw.githubusercontent.com/Drewsif/PiShrink/master/pishrink.sh -O /usr/bin/pishrink.sh && sudo chmod a+x /usr/bin/pishrink.sh
      fi
      sudo /usr/bin/pishrink.sh $STAGE_DIR/otbr.img
      if [[ $SD_CARD ]]; then
        sudo sh -c "dcfldd if=$STAGE_DIR/otbr.img of=$SD_CARD bs=1m && sync"
      fi
      IMG_ZIP_FILE=otbr."$(date +%Y%m%d)".img.zip
      zip "$IMG_ZIP_FILE" "$STAGE_DIR/otbr.img"
      mv "$IMG_ZIP_FILE" "$OUTPUT_DIR"
      sudo umount -lf "${LOOP_NAME}p1"
      sudo umount -lf "${LOOP_NAME}p2"
      sudo losetup -d "${LOOP_NAME}"
  )
}

main "$@"
