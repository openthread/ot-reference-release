# ot-reference-release


## Usage

Clone this repository:

```
$ git clone https://github.com/openthread/ot-reference-release
```

Initialize the submodules:

```
$ git submodule update --init --recursive
```

At the root of the repository:

```
$ REFERENCE_PLATFORM=(nrf52840|efr32mg12|ncs) REFERENCE_RELEASE_TYPE=(certification|1.3)  [SD_CARD=/dev/...] [IN_CHINA=(0|1)] ./script/make-reference-release.bash
```

This will produce a reference release folder in `./build/`. The folder will be
named after the release type, date and the OpenThread commit id.

`SD_CARD` is expected to be the device file path of an SD card inserted to
the host. If this variable is specified, the script will flash the Raspberry Pi
image containing OpenThread border router service to the SD card.

If `IN_CHINA` is set to 1, the script will prefer to use apt sources based in
China so that you can save time while installing software dependencies.

For example, if you are in China and want to flash the built image to an SD card:

```
$ REFERENCE_PLATFORM=nrf52840 REFERENCE_RELEASE_TYPE=certification IN_CHINA=1 SD_CARD=/dev/sda ./script/make-reference-release.bash
```

When `REFERENCE_RELEASE_TYPE` is `certification`, reference release contains following components:
- Raspberry Pi image containing OTBR service and OT Commissioner
- Firmware
- THCI
- Change log
- Quick start guide

When `REFERENCE_RELEASE_TYPE` is `1.3`, reference release contains following components:
- Raspberry Pi image containing OTBR service with border routing feature and service registry feature
- Firmware
- Change log
- Quick start guide

**Note**: Currently, only the following boards are supported for CLI/RCP firmwares:
- nRF52840 dongles
- EFR32MG12 BRD4166A boards

# Contributing

We would love for you to contribute to OpenThread and help make it even better than it is today! See our [Contributing Guidelines](https://github.com/openthread/openthread/blob/main/CONTRIBUTING.md) for more information.

Contributors are required to abide by our [Code of Conduct](https://github.com/openthread/openthread/blob/main/CODE_OF_CONDUCT.md) and [Coding Conventions and Style Guide](https://github.com/openthread/openthread/blob/main/STYLE_GUIDE.md).

# License

OpenThread is released under the [BSD 3-Clause license](https://github.com/openthread/ot-reference-release/blob/main/LICENSE). See the [`LICENSE`](https://github.com/openthread/ot-reference-release/blob/main/LICENSE) file for more information.

Please only use the OpenThread name and marks when accurately referencing this software distribution. Do not use the marks in a way that suggests you are endorsed by or otherwise affiliated with Nest, Google, or The Thread Group.

# Need help?

OpenThread support is available on GitHub:

- Bugs and feature requests pertaining to the Reference Release — [submit to the openthread/ot-reference-release Issue Tracker](https://github.com/openthread/ot-reference-release/issues)
- OpenThread bugs and feature requests — [submit to the OpenThread Issue Tracker](https://github.com/openthread/openthread/issues)
- Community Discussion - [ask questions, share ideas, and engage with other community members](https://github.com/openthread/openthread/discussions)
