#!/usr/bin/env python
#
# Copyright (c) 2019, The OpenThread Authors.
# All rights reserved.

"""
nrf_burn.py
-----------
This script is used to program/verify a group of nRF52840-Dongles in parallel

This script has been tested on Windows 10, macOS 10.14.3 & Debian 4.19.20 using Python 2.7.16
Before you start, please make sure the following requirements be satisfied:
1.install nrfutil (currently only supports Python 2.7)
  -pip install --ignore-installed six nrfutil

2.make sure needed python modules installed:
  pyserial argparse multiprocessing subprocess

3.install pyspinel for checking OT ncp image version (only supports Linux & macOS)
  -git clone git@github.com:openthread/pyspinel.git
  -cd pyspinel
  -sudo python setup.py install

4.if you see unknown device in Windows Device Manager (a yellow triangle mark on 'nRF52840 OpenThread Device')
  after programming OT image to a new device, install "nRF Connect for Windows" for update DFU Trigger diver manually:
   -right-click device and select "Browse my computer for driver software"
   -click "Let me pick from a list of available drivers on my computer"
   -choose "nRF Connect DFU Trigger" from the list and follow the wizard to finish the installation

examples:
1.program two dongles with image file ot-cli-test.zip via port COM1&COM2 and retry 2 times if failed
>python nrf_burn.py -d COM1 COM2 -i ot-cli-test.zip -r 2

2.verify if the version of a group of cli devices in device_file contains string valid_version via cli
>python nrf_burn.py -f device_file -v valid_version -t cli

3.program a group of devices in device_file with image file ot-ncp-test.zip and check if valid_version matches via spinel-cli
>python nrf_burn.py -f device_file -i ot-ncp-test.zip -v valid_version -t ncp

known issue:
 ncp image version verification only supports Linux & macOS

"""
import re
import os
import time
import logging
import serial
import argparse
import subprocess
from multiprocessing import Process, Manager
logging.basicConfig(format='%(message)s', level=logging.DEBUG)

class NrfBurn:

    def __init__(self):
        self.spinel_cmd = ['spinel-cli.py', '-u']
        self.nrfutil_cmd = ['nrfutil', 'dfu', 'serial', '-pkg', '', '-p']
        self.max_connect_times = 5
        self.baudrate = 115200
        self.programmed_flag = 'programmed'
        self.ot_version_prefix = 'OPENTHREAD'

    # use nrfutil program single dev
    def _nrfutil_burn(self, device, image, index, result):
        try:
            self.nrfutil_cmd[4] = image
            self.nrfutil_cmd.append(device)
            p = subprocess.Popen(self.nrfutil_cmd, stdout=subprocess.PIPE)
            time.sleep(1)

            outlines = p.stdout.read()
            p.stdout.close()
            p.wait()

            if self.programmed_flag in outlines:
                result[index] = True
        except Exception as e:
            logging.info('nrfutil program error: {0}'.format(type(e).__name__))
            result[index] = False

    # validate if device's OpenThread version contains "version" via connect type
    def _validate_version(self, device, version, image_type, index, result):
        version_line = ''
        if image_type == 'cli':
            try:
                ser = serial.Serial(device, self.baudrate, timeout=0)
                time.sleep(0.5)
                ser.write(b'\n')
                ser.write(b'version\n')
                time.sleep(0.5)
                count = 1
                while True:
                    response = ser.readline()
                    count += 1
                    if self.ot_version_prefix in response:
                        version_line = response.strip()
                        if version in version_line:
                            result[index] = [True, version_line]
                        else:
                            result[index] = [False, version_line]
                        break
                    if count > self.max_connect_times:
                        result[index] = [False, version_line]
                        break

                    time.sleep(0.5)
                ser.close()
            except Exception as e:
                logging.info('serial communicating error: {0}'.format(type(e).__name__))
                result[index] = [False, str(e)]
        else:
            try:
                self.spinel_cmd.append(device)
                p = subprocess.Popen(self.spinel_cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE)
                time.sleep(1)
                p.stdin.write('version\r\n')
                p.stdin.close()

                output = p.stdout.read()
                p.stdout.close()
                p.wait()

                lines = output.splitlines()
                for line in lines:
                    if self.ot_version_prefix in line:
                        version_line = line.rstrip('\x00')
                        if version in version_line:
                            result[index] = [True, version_line]
                        else:
                            result[index] = [False, version_line]
                        return
                result[index] = [False, version_line]

            except Exception as e:
                logging.info('spinel-cli communicating error: {0}'.format(type(e).__name__))
                result[index] = [False, type(e).__name__]

    # multiprocessing burning image into a bunch of devices
    def program(self, devices, image, retries):
        if not isinstance(devices, list):
            logging.info('invalid device list')
            return False

        program_results = []
        processes = []
        round_results = Manager().list()
        times = retries+1 if retries > 0 else 1
        for device in devices:
            program_results.append([device, False])
            round_results.append('')
        program_round = 0
        try:
            while times:
                times -= 1
                program_round += 1
                for num in range(len(program_results)):
                    if not program_results[num][1]:
                        round_results[num] = ''
                        p = Process(target=self._nrfutil_burn, args=(program_results[num][0], image, num, round_results))
                        processes.append(p)
                        p.start()
                for proc in processes:
                        proc.join()
                if program_round > 1:
                    logging.info('image programming result retry {0}:'.format(program_round-1))
                else:
                    logging.info('image programming result:')
                programmed_device_num = 0
                for num in range(len(program_results)):
                    if round_results[num] != '':
                        program_results[num][1] = round_results[num]
                        if round_results[num]:
                            programmed_device_num += 1
                    logging.info(program_results[num])
                if programmed_device_num == len(program_results):
                    break
            return True
        except Exception as e:
            logging.info('program failed {0}'.format(type(e).__name__))
            return False

    # check a bunch of devices' version and validate if it is correct
    def validate(self, devices, version, image_type, retries):
        if not isinstance(devices, list):
            logging.info('input valid device list')
            return False
        if not version:
            logging.info('input valid version')
            return False
        validate_results = []
        processes = []
        round_results = Manager().list()

        times = retries + 1 if retries > 0 else 1
        for device in devices:
            validate_results.append([device, False, ''])
            round_results.append(['', ''])
        verify_round = 0
        try:
            while times:
                times -= 1
                verify_round += 1
                for num in range(len(validate_results)):
                    if not validate_results[num][1]:
                        round_results[num] = ''
                        p = Process(target=self._validate_version, args=(validate_results[num][0], version, image_type, num, round_results))
                        processes.append(p)
                        p.start()
                for proc in processes:
                    proc.join()
                if verify_round > 1:
                    logging.info('version verification result retry {0}:'.format(verify_round-1))
                else:
                    logging.info('version verification result:')
                verified_device_num = 0
                for num in range(len(validate_results)):
                    if round_results[num][0] != '':
                        validate_results[num][1] = round_results[num][0]
                        validate_results[num][2] = round_results[num][1]
                        if round_results[num][0]:
                            verified_device_num += 1
                    logging.info(validate_results[num])
                if verified_device_num == len(validate_results):
                    break
            return True
        except Exception as e:
            logging.info('validate version failed: {0}'.format(type(e).__name__))
            return False


if __name__ == '__main__':
    device_list = []
    parser = argparse.ArgumentParser(description='program/verify a group of nRF52840-Dongles')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-d',
                       dest='device',
                       nargs='+',
                       help='devices (e.g. COMx, /dev/tty.usbxxx) for programming/verifying')

    group.add_argument('-f',
                       dest='device_file',
                       help='devices from a file (one device per line) for programming/verifying')

    parser.add_argument('-i',
                        dest='image_file',
                        help='image file for programming')

    parser.add_argument('-v',
                        dest='valid_version',
                        help='validate if devices\' version contains valid_version')

    parser.add_argument('-t',
                        dest='image_type',
                        choices=['cli', 'ncp'],
                        help='image type: cli or ncp (associate with -v)')

    parser.add_argument('-r',
                        dest='retries',
                        type=int,
                        help='retry times if failed')

    args = parser.parse_args()

    if (args.valid_version and not args.image_type) or (not args.valid_version and args.image_type):
        parser.error('Both -v and -t should only be set together')

    if args.device:
        if isinstance(args.device, list):
            device_list = args.device
        else:
            parser.error('Invalid device')
        logging.info(args.device)
    if args.device_file:
        if not os.path.exists(args.device_file):
            logging.info(args.device_file + ' not exist')
            exit(1)
        f = open(args.device_file)
        for line in f.readlines():
            line = line.strip()
            if not len(line) or line.startswith('#'):
                continue
            device_list.append(line)
            logging.info(line)
        f.close()
    if not args.image_file and not args.valid_version:
        logging.info('Please input image_file or valid_version')
        exit(1)

    burn = NrfBurn()

    if args.image_file:
        if not os.path.exists(args.image_file):
            logging.info(args.image_file + ' not exist')
            exit(1)
        burn.program(device_list, args.image_file, args.retries)

    if args.valid_version:
        time.sleep(3)
        burn.validate(device_list, args.valid_version, args.image_type, args.retries)

    exit(0)
