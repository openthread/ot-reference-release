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

mkdir -p build

echo "REFERENCE_RELEASE_TYPE=${REFERENCE_RELEASE_TYPE?}"

OUTPUT_ROOT=$(realpath build/ot-"${REFERENCE_RELEASE_TYPE?}-$(date +%Y%m%d)-$(cd openthread && git rev-parse --short HEAD)")

(cd ot-commissioner && git fetch --all && git checkout cert)

mkdir -p "$OUTPUT_ROOT"/fw_dongle/
OUTPUT_ROOT="$OUTPUT_ROOT"/fw_dongle/ ./script/make-firmware.bash

if [ "${REFERENCE_RELEASE_TYPE?}" = "certification" ]; then
  mkdir -p "$OUTPUT_ROOT"/thci
  OUTPUT_ROOT="$OUTPUT_ROOT"/thci/ ./script/make-thci.bash
fi

mkdir -p "$OUTPUT_ROOT"
OUTPUT_ROOT="$OUTPUT_ROOT" ./script/make-raspbian.bash

cp -r doc/* "$OUTPUT_ROOT"
cp -r burn_tool_dongle "$OUTPUT_ROOT"
cp CHANGELOG.txt "$OUTPUT_ROOT"
