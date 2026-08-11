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
| OpenClash 代理插件 | PACKAGES（mihomo 核心已内置，开箱即用） |
| luci-theme-argon 主题 + argon-config | PACKAGES（自带 uci-defaults 自动设为默认主题） |
| 文件管理 / Web 终端 | PACKAGES（`luci-app-filemanager` + `luci-app-ttyd` + 中文语言包） |
| nano 编辑器 | PACKAGES（官方源 9.2，注意 `zip` 创建工具不在官方 feed，需 bsdtar 替代） |

> 官方 x86/64 镜像默认自带 LuCI 全家桶（`luci-ssl` 等），无需重复添加。
> `files/etc/profile` **不要**整体覆盖——官方 profile 里的 `%PATH%` 是构建时替换的
> 占位符；通过 `/etc/profile.d/*.sh`（官方 profile 自动 source）追加即可。

## 第三方包机制

OpenClash / Argon 不在官方 feed 里，workflow 构建时用 `gh release download` 拉取
官方 release 的 **noarch `.apk`** 资产，放进 Image Builder 的 `packages/` 目录——
该目录是官方支持的机制（`README.apk.md`：放入的 `.apk` 会被 `apk mkndx` 生成本地索引并安装）。

- **OpenClash**：跟随 `vernesong/OpenClash` latest release（.apk + .ipk 双资产，取 .apk）。
- **mihomo (meta) 核心**：构建时从 `MetaCubeX/mihomo` latest release 下载
  `mihomo-linux-amd64-compatible`（对 PVE 虚拟机老指令集 CPU 兼容性最好），
  通过 FILES 机制写入 `/etc/openclash/core/clash_meta`（OpenClash 官方指定的核心路径）并保留可执行权限。
  因此**开箱即用，无需再手动下载核心**；如需切换内核版本，到插件设置页的"版本更新"里操作。
- **Argon**：跟随 `jerrykuku/luci-theme-argon` latest release，含主题、配置 app、中文语言包；
  装完自动设为默认主题（自带的 `/etc/uci-defaults/30_luci-theme-argon`）。
  workflow 会自动修复上游 i18n 包的文件名版本号 `.`→`~` 问题（apk 按索引推导文件名）。
- 想锁版本：把 `--pattern` 换成具体文件名，或加 `--tag v0.47.156` 等。

> `ROOTFS_PARTSIZE=256`：官方默认 104MB，OpenClash+mihomo 后 squashfs+overlay 会吃紧，workflow 已调大留余量。

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

## luci-app-rootfs-resize（一键扩容插件）

`luci-app-rootfs-resize/` 是一个独立 LuCI 插件：把 `初始化.md` 的 overlay 扩容流程抽象化，
做成"检测 + 一键扩容"（`parted resizepart → losetup -c → resize2fs`，在线、无需重启）。

- **抽象化**：自动定位 overlay 的 loop 设备 → backing 根分区 → 整个磁盘，
  兼容 `sda2` / `vda2` / `nvme0n1p2` / `mmcblk0p2` 等设备命名，不写死 /dev/sda。
- **结构**：`root/usr/libexec/rootfs-resize.sh`（核心逻辑，输出 JSON）+
  ucode rpcd 后端 + JS view（LuCI 菜单：系统 → Rootfs 扩容）。
- **编译**：`.github/workflows/build-plugin.yml` 用官方 `ghcr.io/openwrt/sdk:x86_64-25.12.5`
  容器直接编出 `.apk`（25.12 为 apk 体系），上传 Artifact，**未加入固件镜像**。
- **设备安装**（未签名包）：
  ```sh
  scp out/luci-app-rootfs-resize-*.apk root@<router>:/tmp/
  ssh root@<router> 'apk add --allow-untrusted /tmp/luci-app-rootfs-resize-*.apk'
  ```
- 依赖（设备需已装，均可 `apk add`）：`luci-base parted losetup resize2fs block-mount`。

## 追官方更新

官方更新对 Image Builder 体系 = **换一个版本号的预编译构建器 + 同版本包源**，内核/kmods 自动配套，无需手动处理。

- 构建 workflow 的 `VERSION` 输入固定官方版本（默认 `25.12.5`），收到更新提醒后把它填成新版本号重建即可。
- `.github/workflows/check-upstream.yml` 每周一 00:00 UTC 自动对比 OpenWrt 最新 stable 与当前默认版本：
  - 有新版本 → 自动开 Issue（含发布说明链接与升级步骤）
  - 已是最新 → 自动关闭残留的更新提醒 Issue
  - 也可在 Actions 手动触发（Run workflow）
- 每次换版本后只需复核两点：**PACKAGES 包名**在新版本源里仍存在（`block-mount` 在 targets feed、`resize2fs` 是独立包）；**`files/` 配置**点版本一般不变，大版本升级前先 diff 官方默认值。

## 限制（Image Builder 方案的边界）

- 内核是预编译的：不能改内核 config / 打内核 patch / 加非官方 kmod（需源码全量编译）。
- 只能针对官方已发布的版本；版本锁定在所选 release。
- 自研 `.apk` 不在官方源里，需要自己编好挂自定义源。
