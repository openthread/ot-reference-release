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

TOOLS_HOME="$HOME"/.cache/tools
[[ -d $TOOLS_HOME ]] || mkdir -p "$TOOLS_HOME"

disable_install_recommends() {
  OTBR_APT_CONF_FILE=/etc/apt/apt.conf

  if [[ -f ${OTBR_APT_CONF_FILE} ]] && grep Install-Recommends "${OTBR_APT_CONF_FILE}"; then
    return 0
  fi

  sudo tee -a /etc/apt/apt.conf <<EOF
APT::Get::Install-Recommends "false";
APT::Get::Install-Suggests "false";
EOF
}

install_common_dependencies() {
  # Common dependencies
  sudo apt-get install --no-install-recommends -y \
    libdbus-1-dev \
    ninja-build \
    expect \
    net-tools \
    libboost-dev \
    libboost-filesystem-dev \
    libboost-system-dev \
    libavahi-common-dev \
    libavahi-client-dev \
    libreadline-dev \
    libncurses-dev \
    libjsoncpp-dev \
    coreutils
}

install_openthread_binaries() {
  pip3 install -U cmake
  cd third_party/openthread/repo
  mkdir -p build && cd build

  cmake .. -GNinja -DOT_PLATFORM=simulation -DOT_FULL_LOGS=1 -DOT_COMMISSIONER=ON -DOT_JOINER=ON
  ninja
  sudo ninja install

  sudo apt-get install --no-install-recommends -y socat
}

configure_network() {
  echo 0 | sudo tee /proc/sys/net/ipv6/conf/all/disable_ipv6
  echo 1 | sudo tee /proc/sys/net/ipv6/conf/all/forwarding
  echo 1 | sudo tee /proc/sys/net/ipv4/conf/all/forwarding
}

disable_install_recommends
sudo apt-get update
install_common_dependencies

if [ "${OTBR_MDNS-}" == 'mDNSResponder' ]; then
  SOURCE_NAME=mDNSResponder-878.30.4
  wget https://opensource.apple.com/tarballs/mDNSResponder/$SOURCE_NAME.tar.gz &&
    tar xvf $SOURCE_NAME.tar.gz &&
    cd $SOURCE_NAME/mDNSPosix &&
    make os=linux && sudo make install os=linux
fi

# Prepare Raspbian image
sudo apt-get install --no-install-recommends --allow-unauthenticated -y qemu qemu-user-static binfmt-support parted dcfldd

pip3 install git-archive-all

IMAGE_NAME=$(basename "${IMAGE_URL}" .zip)
IMAGE_FILE="$IMAGE_NAME".img
[ -f "$TOOLS_HOME"/images/"$IMAGE_FILE" ] || {
  # unit MB
  EXPAND_SIZE=4096

  [ -d "$TOOLS_HOME"/images ] || mkdir -p "$TOOLS_HOME"/images

  [[ -f "$IMAGE_NAME".zip ]] || curl -LO "$IMAGE_URL"

  unzip "$IMAGE_NAME".zip -d /tmp

  (cd /tmp &&
    dd if=/dev/zero bs=1048576 count="$EXPAND_SIZE" >>"$IMAGE_FILE" &&
    mv "$IMAGE_FILE" "$TOOLS_HOME"/images/"$IMAGE_FILE")

  (cd docker-rpi-emu/scripts &&
    sudo ./expand.sh "$TOOLS_HOME"/images/"$IMAGE_FILE" "$EXPAND_SIZE")
}
