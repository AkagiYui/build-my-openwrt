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
| OpenClash geo 数据库 + 大陆白名单 | FILES（GeoIP/GeoSite/ASN/Country + chnroute，构建时拉最新，见下） |
| OpenClash DNS 预置：`enable_custom_dns=1`（保持默认 Dnsmasq 劫持模式，`.lan` 天然不失效） | `files/etc/uci-defaults/90-openclash-dns` |
| OpenClash Web 面板：metacubexd / zashboard | FILES（构建时拉上游 gh-pages 最新版；首次开机把 zashboard 设为默认，见下） |
| luci-theme-argon 主题 + argon-config | PACKAGES（自带 uci-defaults 自动设为默认主题） |
| 文件管理 / Web 终端 | PACKAGES（`luci-app-filemanager` + `luci-app-ttyd` + 中文语言包） |
| UPnP / watchcat / SQM / nlbwmon / vnstat2 | PACKAGES（官方 feed + 中文语言包） |
| Wake-on-LAN 远程开机 | PACKAGES（`luci-app-wol` + `etherwake` 后端 + 中文语言包，已在测试机验证） |
| ddns-go 动态 DNS | FILES（sirpdboy `luci-app-ddns-go` 的 ipk 构建时解包固化，LuCI 界面 + 二进制，见下） |
| WireGuard 接口 | PACKAGES（`luci-proto-wireguard` + `wireguard-tools` + `kmod-wireguard`） |
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
- **geo 数据库 + 大陆白名单**：构建时自动拉取 OpenClash 同源的 4 个 geo 数据文件
  （GeoIP/GeoSite/ASN/Country，见 `openclash_geo.sh`）与大陆白名单
  （`ispip.clang.cn/all_cn.txt` 转 fw4 格式），写入 `/etc/openclash/`，
  开箱即用，无需首启下载；每次构建自动更新到最新。
- **DNS 预置**：`90-openclash-dns` 在首次开机开启 `enable_custom_dns`（让 uci 的
  dns_servers 配置能生效），并启用大陆路由白名单（`china_ip_route=2`，配套预置的
  `china_ip_route.ipset`）。**不预置 nameserver**：保持 OpenClash 默认的
  「本地 DNS 劫持 = Dnsmasq 转发」模式——dnsmasq 先应答 `.lan`/租约、只把外部域名
  转发给内核，局域网解析开 Clash 也不会失效；此时再预置 `127.0.0.1:53` 反而会与
  dnsmasq 的 `server=127.0.0.1#7874` 形成解析环路，故省略。
- **Web 控制面板（metacubexd / zashboard）**：OpenClash `.apk` 内置的 ui 目录是 release
  打包时固化的，会滞后于上游；workflow 构建时直接从上游 gh-pages 分支拉取**最新版**，
  经 FILES 覆盖进 `/usr/share/openclash/ui/`（与插件内"更新面板版本"按钮同源同路径）：
  metacubexd ← `MetaCubeX/metacubexd` gh-pages，zashboard ← `Zephyruso/zashboard` gh-pages-cdn-fonts。
  默认面板由 `files/etc/uci-defaults/91-openclash-default-dashboard` 在首次开机设为
  **zashboard**（仅当仍为出厂默认 metacubexd 时覆盖，用户改过的选择不覆盖）。
- **Argon**：跟随 `jerrykuku/luci-theme-argon` latest release，含主题、配置 app、中文语言包；
  装完自动设为默认主题（自带的 `/etc/uci-defaults/30_luci-theme-argon`）。
  workflow 会自动修复上游 i18n 包的文件名版本号 `.`→`~` 问题（apk 按索引推导文件名）。
- **ddns-go**：官方源没有 ddns-go。跟随 `sirpdboy/luci-app-ddns-go` latest release 的
  `openwrt-24.10-x86_64.tar.gz`（内含 ddns-go 二进制 + LuCI 界面 + 中文包三个 ipk），构建时
  解包 ipk 里的文件进 `files/` 固化——ddns-go 是 Go 静态二进制、luci 部分是 noarch JS/ucode，
  与 25.12 兼容（已在测试机验证）。首次开机由 `files/etc/uci-defaults/99-ddns-go` 创建
  `ddns-go` 降权用户（UID 9000，procd 以非 root 运行）、启用服务并修 rpcd 后端权限。
  LuCI 菜单：**服务 → DDNS-GO**（控制面板 / 基础设置 / 日志）；自带 9876 端口 Web 配置面板。
- 想锁版本：把 `--pattern` 换成具体文件名，或加 `--tag v0.47.156` 等。

> `ROOTFS_PARTSIZE=512`：官方默认 104MB，OpenClash+mihomo+geo 数据库（~40MB）后 squashfs+overlay 会吃紧，workflow 已调大留余量。

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

---

## 附录：第三方源 dl.openwrt.ai（kwrt）调查备份

> 本次调查结论存档，**仅供参考，当前方案未采用**。以下信息若失效，说明该源已不维护，勿沿用。

`dl.openwrt.ai` 是 **kwrt**（openwrt.ai 个人维护的第三方 OpenWrt）的下载站。
它对 x86/64 同时提供固件镜像和 Image Builder，最大的卖点是**官方 feed 之外的第三方包已全部预编译**。

### 资源位置

| 资源 | URL | 说明 |
|---|---|---|
| 版本目录 | `https://dl.openwrt.ai/releases/25.12/targets/x86/64/` | 固件镜像（`kwrt-*.-squashfs-combined[-efi].img.gz`）、`kwrt-imagebuilder-x86-64.Linux-x86_64.tar.zst`（~361MB）、`feeds.buildinfo` / `config.buildinfo` / `version.buildinfo` / `profiles.json` / `sha256sums`、`files/` 子目录 |
| 在线包源 | `https://dl.openwrt.ai/releases/25.12/packages/x86_64/<feed>/` | 真正的包仓库（imagebuilder 的 `repositories.conf` 里写着），每个 feed 下有 `Packages` / `Packages.gz` 索引 |

在线包源按 feed 划分（与 `feeds.buildinfo` 对应）：`base`、`packages`、`luci`、`routing`、`video`、`kiddin9`
（`kiddin9` = `github.com/kiddin9/op-packages`，第三方包的核心来源）。

### 包量级（2026-08 观测）

- 6 个在线源合计 **9824 个独立包**（base 732 / packages 4568 / luci 6708 / routing 56 / video 110 / kiddin9 1000，含多语言包，实际应用约减半）。
- Image Builder tarball 内另打包 1657 个 `.ipk`（够拼默认固件，**不含** OpenClash/PassWall 等，它们在线提供）。
- 默认固件 `.manifest` 共 484 包：预装 `luci-app-passwall`(26.7.1)、`sing-box`、`luci-theme-argon`、`luci-app-filemanager`、`luci-app-ttyd`、`parted`、`resize2fs`、`block-mount`、`nano` 等。

### 代理 / 去广告 / 主题等代表性包（在线源均可按名取）

- 代理：`luci-app-openclash`、`luci-app-passwall`、`luci-app-passwall2`、`luci-app-homeproxy`、`luci-app-ssr-plus`、`luci-app-vssr`、`luci-app-v2raya`、`luci-app-xray`，核心：`mihomo` / `mihomo-meta` / `mihomo-alpha`、`sing-box`、`xray-core`、`v2ray-core`、`hysteria`、`tuic`、`trojan`、`naiveproxy`、`gost`、`brook`。
- DNS/去广告：`luci-app-adguardhome`、`luci-app-smartdns`、`luci-app-mosdns`、`luci-app-chinadns-ng`、`luci-app-adblock`、`luci-app-dnscrypt-proxy2`、`luci-app-https-dns-proxy`。
- 主题：21 个（`luci-theme-argon` / `alpha` / `design` / `kucat` / `material` / `edge` …）。
- 存储/下载：`luci-app-alist`、`aria2`、`qbittorrent`、`transmission`、`filebrowser`、`docker` + `docker-compose`。
- 内网穿透：`frpc`/`frps`、`ddnsto`、`nps`、`tailscale`、`zerotier`。

### 若改用它的影响（取舍）

- ✅ 本仓库 `PACKAGES` 里的项（openclash、mihomo、argon+config、block-mount、resize2fs、parted、filemanager、ttyd、nano、中文包）全部有现成编译产物，**`gh release download` 拉第三方 `.apk` 的机制可整体删除**。
- ⚠️ **`.ipk` 格式**：kwrt `25.12` 名义是 apk 时代，但仓库是 `.ipk`，与官方 25.12 的 apk 体系**不通用**；要利用这些包必须整体换用 kwrt 的 Image Builder。
- ⚠️ **供应链信任**：预编译产物来自第三方，等于信任 Kiddin9 一人及其域名；域名若过期被抢注，CI 可能拿到被篡改的包。
- ⚠️ **非官方内核**：`config.buildinfo` / `version.buildinfo` 与官方不同，出问题无官方背书。
- ⚠️ **不维护后果**：CI 下载 imagebuilder 一步即失败；已刷写的固件不受影响；在线源 URL 逐个验证 `Packages` 是否 200 即可判断存活。
