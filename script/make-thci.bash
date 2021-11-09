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

mkdir -p "$OUTPUT_ROOT"/ot-comm

# Args:
# - $1 - src_path: Source path of the THCI file
# - $2 - out_name: Name of the output file
ncs_adapt()
{
  echo ${1}
  local src_path=${1}
  local out_path="$OUTPUT_ROOT"/${2}

  cp ${src_path} ${out_path}
  sed -i 's/Device : OpenThread/Device : OTNCS/g' ${out_path}
  sed -i 's/Class : OpenThread/Class : OTNCS/g' ${out_path}
  sed -i 's/class OpenThread(/class OTNCS(/g' ${out_path}
  sed -i 's/class OpenThread_/class OTNCS_/g' ${out_path}
  sed -i 's/THCI.OpenThread/THCI.OTNCS/g' ${out_path}
  sed -i 's/super(OpenThread/super(OTNCS/g' ${out_path}
}

src_dir=openthread/tools/harness-thci
(
  case "${REFERENCE_PLATFORM}" in
    nrf*)
      cp ${src_dir}/OpenThread_BR.py "$OUTPUT_ROOT"
      cp ${src_dir}/OpenThread.py "$OUTPUT_ROOT"
      ;;
    ncs*)
      ncs_adapt ${src_dir}/OpenThread.py OTNCS.py
      ncs_adapt ${src_dir}/OpenThread_BR.py OTNCS_BR.py
      ;;
  esac
)

(
  cd ot-commissioner/tools/commissioner_thci
  cp commissioner.py "$OUTPUT_ROOT"/ot-comm
  cp commissioner_impl.py "$OUTPUT_ROOT"/ot-comm
)

sync
