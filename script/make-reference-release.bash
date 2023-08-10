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

main()
{
    # ==========================================================================
    # Prebuild
    # ==========================================================================
    echo "REFERENCE_RELEASE_TYPE=${REFERENCE_RELEASE_TYPE?}"
    mkdir -p build
    OUTPUT_ROOT=$(realpath build/ot-"${REFERENCE_RELEASE_TYPE?}-$(date +%Y%m%d)-$(cd openthread && git rev-parse --short HEAD)")
    mkdir -p "$OUTPUT_ROOT"
    ./script/bootstrap.bash

    # ==========================================================================
    # Build firmware
    # ==========================================================================
    if [ "${REFERENCE_PLATFORM}" != "none" ]; then
        OUTPUT_ROOT="$OUTPUT_ROOT"/fw_dongle_${REFERENCE_PLATFORM}/ ./script/make-firmware.bash "${REFERENCE_PLATFORM}"
    fi

    # ==========================================================================
    # Build THCI
    # ==========================================================================
    if [ "${REFERENCE_RELEASE_TYPE?}" = "1.2" ]; then
        mkdir -p "$OUTPUT_ROOT"/thci
        OUTPUT_ROOT="$OUTPUT_ROOT"/thci/ ./script/make-thci.bash
    fi

    # ==========================================================================
    # Build raspbian
    # ==========================================================================
    mkdir -p "$OUTPUT_ROOT"
    OUTPUT_ROOT="$OUTPUT_ROOT" ./script/make-raspbian.bash

    # ==========================================================================
    # Package docs
    # ==========================================================================
    case "${REFERENCE_PLATFORM}" in
        ncs*)
            cp -r doc/nRF5* "$OUTPUT_ROOT"
            ;;
        *)
            cp -r doc/OpenThread* "$OUTPUT_ROOT"
            ;;
    esac
    cp CHANGELOG.txt "$OUTPUT_ROOT"
}

main "$@"
