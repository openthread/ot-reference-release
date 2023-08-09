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

export LC_ALL=C
export DEBIAN_FRONTEND=noninteractive
export PATH=$PATH:/usr/local/bin

REFERENCE_RELEASE_TYPE=$1
IN_CHINA=$2
REFERENCE_PLATFORM=$3
OPENTHREAD_COMMIT_HASH=$4
OT_BR_POSIX_COMMIT_HASH=$5
OTBR_RCP_BUS=$6
OTBR_RADIO_URL=$7

readonly OTBR_COMMON_OPTIONS=(
    "-DOT_DIAGNOSTIC=ON"
    "-DOT_FULL_LOGS=ON"
    "-DOT_PACKAGE_VERSION=${OPENTHREAD_COMMIT_HASH}"
    "-DOTBR_PACKAGE_VERSION=${OT_BR_POSIX_COMMIT_HASH}"
    "-DOT_POSIX_CONFIG_RCP_BUS=${OTBR_RCP_BUS}"
    "-DOTBR_RADIO_URL=${OTBR_RADIO_URL}"
)

readonly OTBR_THREAD_1_2_OPTIONS=(
    "-DOT_THREAD_VERSION=1.2"
    "-DOTBR_DUA_ROUTING=ON"
    "-DOT_DUA=ON"
    "-DOT_MLR=ON"
    "-DOTBR_DNSSD_DISCOVERY_PROXY=OFF"
    "-DOTBR_SRP_ADVERTISING_PROXY=OFF"
    "-DOTBR_TREL=OFF"
)

readonly OTBR_THREAD_1_3_COMMON_OPTIONS=(
    ${OTBR_COMMON_OPTIONS[@]}
    "-DOTBR_DUA_ROUTING=ON"
    "-DOT_DUA=ON"
    "-DOT_MLR=ON"
    "-DOTBR_DNSSD_DISCOVERY_PROXY=ON"
    "-DOTBR_SRP_ADVERTISING_PROXY=ON"
    "-DOT_BORDER_ROUTING=ON"
    "-DOT_SRP_CLIENT=ON"
    "-DOT_DNS_CLIENT=ON"
)

readonly OTBR_THREAD_1_3_OPTIONS=(
    "-DOT_THREAD_VERSION=1.3"
    "-DOTBR_TREL=OFF"
    "-DOTBR_NAT64=OFF"
)

readonly OTBR_THREAD_1_3_1_OPTIONS=(
    "-DOT_THREAD_VERSION=1.3.1"
    "-DOTBR_TREL=ON"
    "-DOTBR_NAT64=ON"
)

build_options=(
    "INFRA_IF_NAME=eth0"
    "RELEASE=1"
    "REFERENCE_DEVICE=1"
    "BACKBONE_ROUTER=1"
    "NETWORK_MANAGER=0"
    "DHCPV6_PD=0"
    "WEB_GUI=0"
    "REST_API=0"
)

if [ "${REFERENCE_RELEASE_TYPE?}" = "1.2" ]; then
    case "${REFERENCE_PLATFORM}" in
        efr32mg12)
            readonly LOCAL_OPTIONS=(
                'BORDER_ROUTING=0'
                'NAT64=0'
                'DNS64=0'
                "OTBR_OPTIONS=\"${OTBR_THREAD_1_2_OPTIONS[@]} ${OTBR_COMMON_OPTIONS[@]} -DOT_RCP_RESTORATION_MAX_COUNT=100 -DCMAKE_CXX_FLAGS='-DOPENTHREAD_CONFIG_MAC_CSL_REQUEST_AHEAD_US=5000'\""
            )
            build_options+=("${LOCAL_OPTIONS[@]}")
            ;;
        *)
            readonly LOCAL_OPTIONS=(
                'BORDER_ROUTING=0'
                'NAT64=0'
                'DNS64=0'
                "OTBR_OPTIONS=\"${OTBR_THREAD_1_2_OPTIONS[@]} ${OTBR_COMMON_OPTIONS[@]}\""
            )
            build_options+=("${LOCAL_OPTIONS[@]}")
            ;;
    esac
elif [ "${REFERENCE_RELEASE_TYPE?}" = "1.3" ]; then
    case "${REFERENCE_PLATFORM}" in
        efr32mg12)
            readonly LOCAL_OPTIONS=(
                'BORDER_ROUTING=1'
                'NAT64=0'
                'DNS64=0'
                "OTBR_OPTIONS=\"${OTBR_THREAD_1_3_OPTIONS[@]} ${OTBR_THREAD_1_3_COMMON_OPTIONS[@]} -DOT_RCP_RESTORATION_MAX_COUNT=100 -DCMAKE_CXX_FLAGS='-DOPENTHREAD_CONFIG_MAC_CSL_REQUEST_AHEAD_US=5000'\""
            )
            build_options+=("${LOCAL_OPTIONS[@]}")
            ;;
        *)
            readonly LOCAL_OPTIONS=(
                'BORDER_ROUTING=1'
                'NAT64=0'
                'DNS64=0'
                "OTBR_OPTIONS=\"${OTBR_THREAD_1_3_OPTIONS[@]} ${OTBR_THREAD_1_3_COMMON_OPTIONS[@]}\""
            )
            build_options+=("${LOCAL_OPTIONS[@]}")
            ;;
    esac
elif [ "${REFERENCE_RELEASE_TYPE?}" = "1.3.1" ]; then
    case "${REFERENCE_PLATFORM}" in
        efr32mg12)
            readonly LOCAL_OPTIONS=(
                'BORDER_ROUTING=1'
                'NAT64=1'
                'DNS64=1'
                "OTBR_OPTIONS=\"${OTBR_THREAD_1_3_1_OPTIONS[@]} ${OTBR_THREAD_1_3_COMMON_OPTIONS[@]} -DOT_RCP_RESTORATION_MAX_COUNT=100\""
            )
            build_options+=("${LOCAL_OPTIONS[@]}")
            ;;
        *)
            readonly LOCAL_OPTIONS=(
                'BORDER_ROUTING=1'
                'NAT64=1'
                'DNS64=1'
                "OTBR_OPTIONS=\"${OTBR_THREAD_1_3_1_OPTIONS[@]} ${OTBR_THREAD_1_3_COMMON_OPTIONS[@]}\""
            )
            build_options+=("${LOCAL_OPTIONS[@]}")
            ;;
    esac
fi

configure_apt_source()
{
    if [ "$IN_CHINA" = 1 ]; then
        echo 'deb http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ buster main non-free contrib rpi
deb-src http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ buster main non-free contrib rpi' | sudo tee /etc/apt/sources.list
        echo 'deb http://mirrors.tuna.tsinghua.edu.cn/raspberrypi/ buster main ui' | sudo tee /etc/apt/sources.list.d/raspi.list
    fi
}
configure_apt_source

echo "127.0.0.1 $(hostname)" >>/etc/hosts
chown -R pi:pi /home/pi/repo
cd /home/pi/repo/ot-br-posix
apt-get update
apt-get install -y --no-install-recommends git python3-pip
su -c "${build_options[*]} script/bootstrap" pi

rm -rf /home/pi/repo/ot-br-posix/third_party/openthread/repo
cp -r /home/pi/repo/openthread /home/pi/repo/ot-br-posix/third_party/openthread/repo

# Pin CMake version to 3.10.3 for issue https://github.com/openthread/ot-br-posix/issues/728.
# For more background, see https://gitlab.kitware.com/cmake/cmake/-/issues/20568.
apt-get purge -y cmake
pip3 install scikit-build
pip3 install cmake==3.10.3
cmake --version

pip3 install zeroconf

su -c "${build_options[*]} script/setup" pi || true

if [ "$REFERENCE_RELEASE_TYPE" = "1.2" ]; then
    cd /home/pi/repo/
    ./script/make-commissioner.bash
fi

# nRF Connect SDK related actions
if [ "${REFERENCE_PLATFORM?}" = "ncs" ]; then
    wget https://bootstrap.pypa.io/pip/2.7/get-pip.py
    sudo python2 get-pip.py
    apt-get install -y --no-install-recommends vim wiringpi
    pip install wrapt==1.12.1
    pip install nrfutil

    # add calling of link_dongle.py script at startup to update symlink to the dongle
    sed -i '/exit 0/d' /etc/rc.local
    grep -qxF 'sudo systemctl restart otbr-agent.service' /etc/rc.local || echo 'sudo systemctl restart otbr-agent.service' >>/etc/rc.local
    echo 'exit 0' >>/etc/rc.local

    # update testharness-discovery script to fix autodiscovery issue
    if [ "$REFERENCE_RELEASE_TYPE" = "1.2" ]; then
        sed -i 's/OpenThread_BR/OTNCS_BR/g' /usr/sbin/testharness-discovery
    else
        sed -i 's/OpenThread_BR/OTNCS13_BR/g' /usr/sbin/testharness-discovery
    fi

elif [ "${REFERENCE_PLATFORM?}" = "efr32mg12" ]; then
    # update testharness-discovery script to fix autodiscovery issue
    sed -i "s/OpenThread_BR/OTS${REFERENCE_RELEASE_TYPE//./}_BR/g" /usr/sbin/testharness-discovery
fi

sync
