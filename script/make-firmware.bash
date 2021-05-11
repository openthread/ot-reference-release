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

echo "OUTPUT_DIR=${OUTPUT_DIR?}"

PLATFORM=nrf52840

BUILD_OPTIONS='-DOT_BOOTLOADER=USB '
BUILD_OPTIONS+='-DOT_REFERENCE_DEVICE=ON '
BUILD_OPTIONS+='-DOT_BORDER_ROUTER=ON '
BUILD_OPTIONS+='-DOT_SERVICE=ON '
BUILD_OPTIONS+='-DOT_COMMISSIONER=ON '
BUILD_OPTIONS+='-DOT_JOINER=ON '
BUILD_OPTIONS+='-DOT_MAC_FILTER=ON '
BUILD_OPTIONS+='-DOT_DUA=ON '
BUILD_OPTIONS+='-DOT_MLR=ON '
BUILD_OPTIONS+='-DBORDER_AGENT=OFF '
BUILD_OPTIONS+='-DOT_COAP=OFF '
BUILD_OPTIONS+='-DOT_COAPS=OFF '
BUILD_OPTIONS+='-DOT_ECDSA=OFF '
BUILD_OPTIONS+='-DOT_FULL_LOGS=OFF '
BUILD_OPTIONS+='-DOT_IP6_FRAGM=OFF '
BUILD_OPTIONS+='-DOT_LINK_RAW=OFF '
BUILD_OPTIONS+='-DOT_MTD_NETDIAG=OFF '
BUILD_OPTIONS+='-DOT_SNTP_CLIENT=OFF '
BUILD_OPTIONS+='-DOT_UDP_FORWARD=OFF '

cd ot-nrf528xx

NRFUTIL=/tmp/nrfutil-linux
if [ ! -f $NRFUTIL ]; then
	wget https://github.com/NordicSemiconductor/pc-nrfutil/releases/download/v6.1/nrfutil-linux -o $NRFUTIL
	chmod +x $NRFUTIL
fi

./script/build $PLATFORM USB_trans -DOT_THREAD_VERSION=1.2 "$BUILD_OPTIONS"

$NRFUTIL keys generate private.pem

make_zip() {
	arm-none-eabi-objcopy -O ihex ./build/bin/"$1" "$1".hex
	$NRFUTIL pkg generate --debug-mode --hw-version 52 --sd-req 0 --application "$1".hex --key-file private.pem "$1".zip
}

make_zip "ot-cli-ftd"
mv ot-cli-ftd.zip ot-cli-ftd-1.2.zip
make_zip "ot-rcp"

./script/build $PLATFORM USB_trans -DOT_THREAD_VERSION=1.1 "$BUILD_OPTIONS"
make_zip "ot-cli-ftd"
mv ot-cli-ftd.zip ot-cli-ftd-1.1.zip

mkdir -p "$OUTPUT_DIR"
mv ./*.zip "$OUTPUT_DIR"
