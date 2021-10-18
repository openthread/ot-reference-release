#!/usr/bin/python3
import shlex
import subprocess as sub
from pathlib import Path
import re
import logging

NORDIC_DEVICE_REGEX = 'usb-Nordic_Semiconductor_ASA_Thread_Co-Processor_\w+-if00'
SYMLINKS_PATH = '/dev/serial/by-id'
OTBR_AGENT_DEFAULTS = '/etc/default/otbr-agent'

logging.basicConfig(format='%(asctime)s %(levelname)-8s %(message)s',
                    level=logging.DEBUG,
                    datefmt='%Y-%m-%d %H:%M:%S',
                    filename=str(Path(__file__).parent.joinpath(Path(__file__).stem + '.log'))
                    )


def get_dongle_symlink():
    proc = sub.Popen(shlex.split(f'ls -1 {SYMLINKS_PATH}'), stdout=sub.PIPE, stderr=sub.PIPE)
    stdout, stderr = proc.communicate()
    if proc.returncode != 0:
        raise Exception("Cannot detect nRF52840 dongle. Check connection.")

    devices = list()
    for line in stdout.decode().split('\n'):
        if re.search(NORDIC_DEVICE_REGEX, line):
            dev = line.split('->')[0].strip()
            devices.append(dev)
    if len(devices) > 1:
        raise Exception(f"There is more than expected devices connected: {' '.join(devices)}")
    if len(devices) == 0:
        raise Exception("Cannot detect nRF52840 dongle. Check connection.")
    return str(Path(SYMLINKS_PATH).joinpath(devices[0]))


def edit_otbr_defaults(device_path):
    dev_regex = r'(OTBR_AGENT_OPTS=\"-I wpan0 -B eth0 spinel\+hdlc\+uart://).*?( trel://eth0")'
    if not Path(OTBR_AGENT_DEFAULTS).exists():
        raise Exception(f'Cannot find file {OTBR_AGENT_DEFAULTS}')
    with open(OTBR_AGENT_DEFAULTS, 'r') as fh:
        content = fh.read()
        re.search(dev_regex, content)
        new_content = re.sub(
            dev_regex, fr'\g<1>{device_path}?uart-reset\g<2>', content)
    logging.info(f"New content of {OTBR_AGENT_DEFAULTS}:\n{new_content}")
    with open(OTBR_AGENT_DEFAULTS, 'w') as fh:
        fh.write(new_content)
    logging.info(f"New content written to {OTBR_AGENT_DEFAULTS}")


if __name__ == '__main__':
    dongle_path = get_dongle_symlink()
    logging.info(f"nRF52840 dongle symlink: {dongle_path}")
    edit_otbr_defaults(device_path=dongle_path)
