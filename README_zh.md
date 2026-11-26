## ADB Disabler

[English](README.md) 

- Magisk / KernelSU / APatch 通用
- 开机自动禁用 开发者选项 / USB调试 / OEM 解锁

## 安装

下载 `ADB-Disabler-1.1.0.zip`，在管理器里刷入重启

| 管理器 | 版本要求 |
|---|---|
| Magisk | 20.4+ |
| KernelSU | 0.9.0+ |
| APatch | 10.7+ |

## WebUI

| 管理器 | 打开方式 |
|---|---|
| KernelSU / KernelSU Next | 模块卡片 → WebUI |
| APatch | 模块卡片 → WebUI |
| Magisk | 安装 [MMRL](https://github.com/MMRLApp/MMRL)，并在模块设置中允许 **高级 KernelSU API** |

界面基于 [miuix-vue](https://github.com/YuKongA/miuix-vue)构建，采用 Miuix / HyperOS 设计语言。

## 构建

```sh
python3 build.py
```