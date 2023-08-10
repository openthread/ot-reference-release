#!/bin/bash
#
#  Copyright (c) 2023, The OpenThread Authors.
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

# ==============================================================================
# Bash definitions

if [[ -n ${BASH_SOURCE[0]} ]]; then
    script_path="${BASH_SOURCE[0]}"
else
    script_path="$0"
fi
script_dir="$(realpath "$(dirname "${script_path}")")"
repo_dir="$(dirname "${script_dir}")"

# ==============================================================================

install_packages_apt()
{
    echo 'Installing apt dependencies...'

    # apt-get update and install dependencies
    sudo apt-get update
    sudo apt-get --no-install-recommends install -y \
        parted \
        fdisk \
        git \
        wget \
        file \
        xz-utils \
        zip \
        python3-pip \
        dcfldd \
        lsof
}

install_packages_opkg()
{
    echo 'opkg not supported currently' && false
}

install_packages_rpm()
{
    echo 'rpm not supported currently' && false
}

install_packages_brew()
{
    echo 'brew not supported currently' && false
}

install_packages_source()
{
    echo 'source not supported currently' && false
}

install_packages_pip3()
{
    echo 'Installing python3 dependencies...'
    pip3 install --upgrade -r "${repo_dir}/requirements.txt"
}

install_packages()
{
    PM=source
    if command -v apt-get; then
        PM=apt
    elif command -v rpm; then
        PM=rpm
    elif command -v opkg; then
        PM=opkg
    elif command -v brew; then
        PM=brew
    fi
    install_packages_$PM

    if command -v pip3; then
        install_packages_pip3
    fi
}

install_qemu()
{
    # Different versions of Linux may support qemu or qemu-system-arm.
    # Search for the correct one to install
    if apt-cache search '^qemu$' | grep -q 'qemu'; then
        QEMU=qemu
    elif apt-cache search '^qemu-system-arm$' | grep -q 'qemu-system-arm'; then
        QEMU=qemu-system-arm
    else
        echo "ERROR: Could not find 'qemu' or 'qemu-system-arm'"
        exit 1
    fi

    sudo apt-get install --no-install-recommends --allow-unauthenticated -y \
        $QEMU \
        qemu-user-static \
        binfmt-support
}

main()
{
    if [ $# == 0 ]; then
        install_packages
        install_qemu
    elif [ "$1" == 'packages' ]; then
        install_packages
    elif [ "$1" == 'python' ]; then
        install_packages_pip3
    elif [ "$1" == 'qemu' ]; then
        install_qemu
    else
        echo >&2 "Unsupported action: $1. Supported: packages, python, qemu"
        # 128 for Invalid arguments
        exit 128
    fi

    echo "Bootstrap completed successfully."
}

main "$@"
