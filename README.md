# ot-reference-release


## Usage

At the root of the repository:

```
$ REFERENCE_RELEASE_TYPE=(certification|1.3)  [SD_CARD=/dev/...] [IN_CHINA=(0|1)] ./script/make-reference-release.bash
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
$ REFERENCE_RELEASE_TYPE=certification IN_CHINA=1 SD_CARD=/dev/sda ./script/make-reference-release.bash 
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
