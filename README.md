## ADB Disabler

[简体中文](README_zh.md)

- Compatible with Magisk / KernelSU / APatch
- Automatically disables Developer options / USB debugging / OEM unlocking at boot

## Install

Download `ADB-Disabler-1.1.0.zip`, flash it in your manager, and reboot.

| Manager | Version |
|---|---|
| Magisk | 20.4+ |
| KernelSU | 0.9.0+ |
| APatch | 10.7+ |

## WebUI

| Manager | How to open |
|---|---|
| KernelSU / KernelSU Next | Module card → WebUI |
| APatch | Module card → WebUI |
| Magisk | Install [MMRL](https://github.com/MMRLApp/MMRL), then allow **Advanced KernelSU API** in the module settings |

The interface is built with [miuix-vue](https://github.com/YuKongA/miuix-vue)
and follows the Miuix / HyperOS design language.

## Build

```sh
python3 build.py
```
