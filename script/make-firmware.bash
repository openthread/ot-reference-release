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

# Global Vars
platform=""
build_dir=""
NRFUTIL=""

readonly OT_PLATFORMS=(nrf52840 efr32mg12 ncs)

readonly build_1_3_options_common=(
    "-DOT_SRP_SERVER=ON"
    "-DOT_ECDSA=ON"
    "-DOT_SERVICE=ON"
    "-DOT_DNSSD_SERVER=ON"
    "-DOT_SRP_CLIENT=ON"
)

readonly build_1_3_options_efr32=(
    ""
)

readonly build_1_3_options_nrf=(
    ""
)

readonly build_1_2_options_common=(
    '-DOT_THREAD_VERSION=1.2'
    '-DOT_REFERENCE_DEVICE=ON'
    '-DOT_BORDER_ROUTER=ON'
    '-DOT_SERVICE=ON'
    '-DOT_COMMISSIONER=ON'
    '-DOT_JOINER=ON'
    '-DOT_MAC_FILTER=ON'
    '-DOT_DHCP6_SERVER=ON'
    '-DOT_DHCP6_CLIENT=ON'
    '-DOT_DUA=ON'
    '-DOT_MLR=ON'
    '-DOT_LINK_METRICS_INITIATOR=ON'
    '-DOT_LINK_METRICS_SUBJECT=ON'
    '-DOT_CSL_RECEIVER=ON'
    '-DOT_BORDER_AGENT=OFF'
    '-DOT_COAP=OFF'
    '-DOT_COAPS=OFF'
    '-DOT_ECDSA=OFF'
    '-DOT_FULL_LOGS=OFF'
    '-DOT_IP6_FRAGM=OFF'
    '-DOT_LINK_RAW=OFF'
    '-DOT_MTD_NETDIAG=OFF'
    '-DOT_SNTP_CLIENT=OFF'
    '-DOT_UDP_FORWARD=OFF'
)

readonly build_1_2_options_nrf=(
    '-DOT_BOOTLOADER=USB'
    '-DOT_CSL_RECEIVER=ON'
)

readonly build_1_1_env_common=(
    'BORDER_ROUTER=1'
    'REFERENCE_DEVICE=1'
    'COMMISSIONER=1'
    'DHCP6_CLIENT=1'
    'DHCP6_SERVER=1'
    'JOINER=1'
    'MAC_FILTER=1'
    'BOOTLOADER=USB'
)

readonly build_1_1_env_nrf=(
    'USB=1'
)

# Args
# - $1: The name of the hex file to zip
# - $2: The basename of the file
# - $3: Thread version number, e.g. 1.2
# - $4: Timestamp
# - $5: Commit ID
distribute()
{
    local hex_file=$1
    local zip_file="$2-$3-$4-$5.zip"

    case "${platform}" in
        nrf*|ncs*)
            ${NRFUTIL} pkg generate --debug-mode --hw-version 52 --sd-req 0 --application "${hex_file}" --key-file /tmp/private.pem "${zip_file}"
            ;;
        *)
            zip "${zip_file}" "${hex_file}"
            ;;
    esac

    mv "${zip_file}" "$OUTPUT_ROOT"
}

# Environment Vars
# - $thread_version: Thread version number, e.g. 1.2
# Args
# - $1: The basename of the file to zip, e.g. ot-cli-ftd
# - $2: The binary path (optional)
package_ot()
{
    # Parse Args
    local basename=${1?Please specify app basename}
    local binary_path=${2:-"${build_dir}/bin/${basename}"}
    thread_version=${thread_version?}

    # Get build info
    local commit_id
    local timestamp
    commit_id=$(cd "${repo_dir}"/openthread && git rev-parse --short HEAD)
    timestamp=$(date +%Y%m%d)

    # Generate .hex file
    local hex_file="${basename}"-"${thread_version}".hex
    if [ ! -f "$binary_path" ]; then
        echo "WARN: $binary_path does not exist. Skipping packaging"
        return
    fi
    arm-none-eabi-objcopy -O ihex "$binary_path" "${hex_file}"

    # Distribute
    distribute "${hex_file}" "${basename}" "${thread_version}" "${timestamp}" "${commit_id}"
}

# Envionment variables:
# - build_type:             Type of build (optional)
# - build_script_flags:     Any flags specific to the platform repo's build script (optional)
# Args:
# - $1 - thread_version: Thread version number, e.g. 1.2
# - $2 - platform_repo:  Path to platform's repo, e.g. ot-efr32, ot-nrf528xx
build_ot()
{
    thread_version=${thread_version?}
    platform_repo=${platform_repo?}

    mkdir -p "$OUTPUT_ROOT"

    case "${thread_version}" in
        # Build OpenThread 1.2
        "1.2")
            cd "${platform_repo}"
            git clean -xfd

            # Use OpenThread from top-level of repo
            rm -rf openthread
            ln -s ../openthread .

            # Build
            build_dir=${OT_CMAKE_BUILD_DIR:-"${repo_dir}"/build-"${thread_version}"/"${platform}"}
            OT_CMAKE_BUILD_DIR="${build_dir}" ./script/build ${build_script_flags:-} "${platform}" ${build_type:-} "$@"

            # Package and distribute
            local dist_apps=(
                ot-cli-ftd
                ot-rcp
            )
            for app in "${dist_apps[@]}"; do
                package_ot "${app}"
            done

            # Clean up
            git clean -xfd
            ;;

        # Build OpenThread 1.1
        "1.1")
            cd openthread-1.1

            # Prep
            git clean -xfd
            ./bootstrap

            # Build
            make -f examples/Makefile-"${platform}" "${options[@]}"

            # Package and distribute
            local dist_apps=(
                ot-cli-ftd
                ot-rcp
            )
            for app in "${dist_apps[@]}"; do
                package_ot "${app}" "${thread_version}" output/"${platform}"/bin/"${app}"
            done

            # Clean up
            git clean -xfd
            ;;
    esac

    cd "${repo_dir}"
}

die() { echo "$*" 1>&2 ; exit 1; }

nrfutil_setup()
{
    # Setup nrfutil
    if [[ $OSTYPE == "linux"* ]]; then
        ostype=linux
    elif [[ $OSTYPE == "darwin"* ]]; then
        ostype=mac
    fi
    NRFUTIL=/tmp/nrfutil-${ostype}

    if [ ! -f $NRFUTIL ]; then
        wget -O $NRFUTIL https://github.com/NordicSemiconductor/pc-nrfutil/releases/download/v6.1.2/nrfutil-${ostype}
        chmod +x $NRFUTIL
    fi

    # Generate private key
    if [ ! -f /tmp/private.pem ]; then
        $NRFUTIL keys generate /tmp/private.pem
    fi
}

build()
{
    if [ "${REFERENCE_RELEASE_TYPE?}" = "certification" ]; then
        build_1_2_options=("${build_1_2_options_common[@]}")
        build_1_1_env=("${build_1_1_env_common[@]}")

        case "${platform}" in
            nrf*)
                build_1_2_options+=("${build_1_2_options_nrf[@]}")
                build_1_1_env+=("${build_1_1_env_nrf[@]}")
                platform_repo=ot-nrf528xx

                thread_version=1.2 build_type="USB_trans" build_ot "${build_1_2_options[@]}" "$@"
                thread_version=1.1 build_type="USB_trans" build_ot "${build_1_1_env[@]}" "$@"
                ;;
        esac
    elif [ "${REFERENCE_RELEASE_TYPE}" = "1.3" ]; then
        options=("${build_1_3_options_common[@]}")

        case "${platform}" in
            nrf*)
                options+=("${build_1_3_options_nrf[@]}")
                platform_repo=ot-nrf528xx

                thread_version=1.2 build_type="USB_trans" build_ot "${options[@]}" "$@"
                ;;
            efr32mg12)
                options+=("${build_1_3_options_efr32[@]}")
                platform_repo=ot-efr32

                thread_version=1.2 build_script_flags="--skip-silabs-apps" build_ot "-DBOARD=brd4166a" "${options[@]}" "$@"
                ;;
        esac
    else
        die "Error: REFERENCE_RELEASE_TYPE = ${REFERENCE_RELEASE_TYPE} is unsupported"
    fi
}

deploy_ncs()
{
    local commit_hash=$(<${script_dir}'/../config/ncs/sdk-nrf-commit')

    sudo apt install --no-install-recommends git cmake ninja-build gperf \
        ccache dfu-util device-tree-compiler wget \
        python3-dev python3-pip python3-setuptools python3-tk python3-wheel xz-utils file \
        make gcc gcc-multilib g++-multilib libsdl2-dev
    pip3 install --user west
    mkdir -p ${script_dir}/../ncs
    cd ${script_dir}/../ncs
    unset ZEPHYR_BASE
    west init -m https://github.com/nrfconnect/sdk-nrf --mr main || true
    cd nrf
    git fetch origin
    git reset --hard "$commit_hash" || die "ERROR: unable to checkout the specified sdk-nrf commit."
    west update -n -o=--depth=1
    cd ..
    pip3 install --user -r zephyr/scripts/requirements.txt
    pip3 install --user -r nrf/scripts/requirements.txt
    pip3 install --user -r bootloader/mcuboot/scripts/requirements.txt
    source zephyr/zephyr-env.sh
    west config manifest.path nrf
}

package_ncs()
{
    # Get build info
    local commit_id=$(git rev-parse --short HEAD)
    local timestamp=$(date +%Y%m%d)

    distribute "/tmp/ncs_cli_1_1/zephyr/zephyr.hex" "ot-cli-ftd" "1.1" "${timestamp}" "${commit_id}"
    distribute "/tmp/ncs_cli_1_2/zephyr/zephyr.hex" "ot-cli-ftd" "1.2" "${timestamp}" "${commit_id}"
    distribute "/tmp/ncs_rcp_1_2/zephyr/zephyr.hex" "ot-rcp" "1.2" "${timestamp}" "${commit_id}"
}

build_ncs()
{
  mkdir -p "$OUTPUT_ROOT"
  deploy_ncs

  # Build folder | nrf-sdk sample | Sample configuration
  local cli_1_1=("/tmp/ncs_cli_1_1" "samples/openthread/cli/" "${script_dir}/../config/ncs/overlay-cli-1_1.conf")
  local cli_1_2=("/tmp/ncs_cli_1_2" "samples/openthread/cli/" "${script_dir}/../config/ncs/overlay-cli-1_2.conf")
  local rcp_1_2=("/tmp/ncs_rcp_1_2" "samples/openthread/coprocessor/" "${script_dir}/../config/ncs/overlay-rcp-1_2.conf")
  local variants=(cli_1_1[@] cli_1_2[@] rcp_1_2[@])

  cd nrf
  for variant in ${variants[@]}; do
      west build -d ${!variant:0:1} -b nrf52840dongle_nrf52840 -p always ${!variant:1:1} -- -DOVERLAY_CONFIG=${!variant:2:1} -DDTC_OVERLAY_FILE=usb.overlay
  done

  package_ncs "ot-cli-ftd" "1.1"
  package_ncs "ot-cli-ftd" "1.2"
  package_ncs "ot-rcp" "1.2"
}

main()
{
    local platforms=()

    if [[ $# == 0 ]]; then
        platforms=("${OT_PLATFORMS[@]}")
    else
        platforms=("$1")
        shift
    fi

    # Print OUTPUT_ROOT. Error if OUTPUT_ROOT is not defined
    OUTPUT_ROOT=$(realpath "${OUTPUT_ROOT?}")
    echo "OUTPUT_ROOT=${OUTPUT_ROOT}"
    mkdir -p "${OUTPUT_ROOT}"

    for p in "${platforms[@]}"; do
        # Check if the platform is supported.
        echo "${OT_PLATFORMS[@]}" | grep -wq "${p}" || die "ERROR: Unsupported platform: ${p}"
        printf "\n\n======================================\nBuilding firmware for %s\n======================================\n\n" "${p}"
        platform=${p}
        case "${platform}" in
            nrf*|ncs*)
                nrfutil_setup
                ;;
        esac
        case "${platform}" in
            ncs*)
                build_ncs
                ;;
            *)
                build
                ;;
        esac
    done

}

main "$@"
