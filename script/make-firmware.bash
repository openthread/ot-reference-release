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

echo "OUTPUT_ROOT=${OUTPUT_ROOT?}"

readonly PLATFORM=nrf52840

readonly BUILD_OPTIONS=('-DOT_BOOTLOADER=USB'
  '-DOT_REFERENCE_DEVICE=ON'
  '-DOT_BORDER_ROUTER=ON'
  '-DOT_SERVICE=ON'
  '-DOT_COMMISSIONER=ON'
  '-DOT_JOINER=ON'
  '-DOT_MAC_FILTER=ON'
  '-DOT_DUA=ON'
  '-DOT_MLR=ON'
  '-DBORDER_AGENT=OFF'
  '-DOT_COAP=OFF'
  '-DOT_COAPS=OFF'
  '-DOT_ECDSA=OFF'
  '-DOT_FULL_LOGS=OFF'
  '-DOT_IP6_FRAGM=OFF'
  '-DOT_LINK_RAW=OFF'
  '-DOT_MTD_NETDIAG=OFF'
  '-DOT_SNTP_CLIENT=OFF'
  '-DOT_UDP_FORWARD=OFF')

cd ot-nrf528xx

NRFUTIL=/tmp/nrfutil-linux
if [ ! -f $NRFUTIL ]; then
  wget -O $NRFUTIL https://github.com/NordicSemiconductor/pc-nrfutil/releases/download/v6.1/nrfutil-linux
  chmod +x $NRFUTIL
fi

$NRFUTIL keys generate private.pem

# $1: The basename of the file to zip, e.g. ot-cli-ftd
# $2: Thread version number, e.g. 1.2
make_zip() {
  arm-none-eabi-objcopy -O ihex ./build-"$2"/bin/"$1" "$1"-"$2".hex
  $NRFUTIL pkg generate --debug-mode --hw-version 52 --sd-req 0 --application "$1"-"$2".hex --key-file private.pem "$1"-"$2".zip
}

if [ "${THREAD_VERSION?}" = "1.2" ]; then
  OT_CMAKE_BUILD_DIR=build-1.2 ./script/build $PLATFORM USB_trans -DOT_THREAD_VERSION=1.2 "${BUILD_OPTIONS[*]}"
  make_zip ot-cli-ftd 1.2
  make_zip ot-rcp 1.2

  OT_CMAKE_BUILD_DIR=build-1.1 ./script/build $PLATFORM USB_trans -DOT_THREAD_VERSION=1.1 "${BUILD_OPTIONS[*]}"
  make_zip ot-cli-ftd 1.1
elif [ "${THREAD_VERSION}" = "duckhorn" ]; then
  OT_CMAKE_BUILD_DIR=build-1.2 ./script/build $PLATFORM USB_trans -DOT_THREAD_VERSION=1.2
  make_zip ot-rcp 1.2
fi

mkdir -p "$OUTPUT_ROOT"
mv ./*.zip "$OUTPUT_ROOT"
