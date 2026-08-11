# build-my-openwrt

基于**官方 OpenWrt Image Builder** 构建 `x86_64 generic squashfs-combined-efi` 镜像，
并把 `初始化.md` 里的运行时 `apk add` 与配置改动**提前固化进镜像**，部署后开箱即用。

## 原理

OpenWrt 官方把构建拆成四层：工具链 → 内核 → 包(.apk) → 组装镜像。
Image Builder 是官方 buildbot 完成前三层后只把"组装"留给你的产物
（46MB 归档，含预编译 `bzImage`、整套 `.apk` 包仓库和镜像生成脚本），
因此 `make image` 只是**装配**（选包 → 拼 rootfs → 打 GPT 分区 → 出镜像），
几分钟出镜像，产物与官方同源同构。

> 官方文档：https://openwrt.org/docs/guide-user/additional-software/imagebuilder

## 已固化的内容（对应 初始化.md）

| 文档里的运行时操作 | 本仓库固化方式 |
|---|---|
| `apk add luci-i18n-base-zh-cn` | PACKAGES |
| `apk add block-mount` | PACKAGES |
| `apk add openssh-sftp-server` + dropbear restart | PACKAGES |
| `apk add losetup / e2fsprogs / resize2fs` | PACKAGES（`resize2fs` 是独立包，官方镜像只带 e2fsprogs） |
| `apk add btop` + `LC_ALL=C.UTF-8` | PACKAGES + `files/etc/profile.d/99-locale.sh` |
| uci 设置 Asia/Singapore `<+08>-8` | `files/etc/config/system` |
| 修改 IP / 网关 / DNS | `files/etc/config/network`（默认 192.168.1.1，改这里） |
| `parted` 扩分区（文档步骤） | PACKAGES（为未来的 luci 一键扩容插件预装） |

> 官方 x86/64 镜像默认自带 LuCI 全家桶（`luci-ssl` 等），无需重复添加。
> `files/etc/profile` **不要**整体覆盖——官方 profile 里的 `%PATH%` 是构建时替换的
> 占位符；通过 `/etc/profile.d/*.sh`（官方 profile 自动 source）追加即可。

## 产物

`make image PROFILE=generic` 默认产出（`bin/targets/x86/64/`）：

- `openwrt-25.12.5-x86-64-generic-squashfs-combined-efi.img.gz` ← PVE UEFI 用这个
- `...-squashfs-combined.img.gz`（legacy BIOS）
- `...-ext4-combined-efi.img.gz`、rootfs 等

PVE 部署参数（对应文档）：`--machine q35 --bios ovmf --efidisk0 ... --boot order=scsi0`。

## 触发构建

- **手动**：Actions → *Build OpenWrt x86_64 combined-efi* → Run workflow（可选填版本号，默认 25.12.5）
- **自动**：push 修改 `files/**` 或本 workflow 时触发

产物从 Actions 页面的 Artifacts 下载。

## 自定义

- **加包**：编辑 `.github/workflows/build-openwrt.yml` 里的 `PACKAGES="..."`。
- **改配置**：编辑 `files/` 目录下的文件（会覆盖镜像内同名文件）。
- **升级版本**：Run workflow 时填新版本号（如 `25.12.6`），或改 workflow 默认值。
- **luci 插件**：用官方 SDK / `openwrt/gh-action-sdk` 把插件编成 `.apk` 发布，
  构建时通过自定义源加入 `PACKAGES`，无需源码全量编译。

## 限制（Image Builder 方案的边界）

- 内核是预编译的：不能改内核 config / 打内核 patch / 加非官方 kmod（需源码全量编译）。
- 只能针对官方已发布的版本；版本锁定在所选 release。
- 自研 `.apk` 不在官方源里，需要自己编好挂自定义源。
