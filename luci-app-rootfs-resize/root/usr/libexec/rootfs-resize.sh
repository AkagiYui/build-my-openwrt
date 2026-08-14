#!/bin/sh
# luci-app-rootfs-resize 后端脚本
#
# 抽象化自 PVE 部署文档的 overlay 扩容流程:
#   parted -s <disk> resizepart <part> 100%
#   losetup -c <loop>
#   resize2fs <loop>
#
# 适配要点:
#   - 自动定位 overlay 的 loop 设备 -> backing 根分区 -> 整个磁盘
#   - 兼容常见设备命名: sda2 / vda2 / nvme0n1p2 / mmcblk0p2
#   - 全程只读检测 (status) 与在线扩容 (resize, 无需重启)
#
# 用法: rootfs-resize.sh status | resize
# status 输出 JSON 供 LuCI 前端渲染; resize 输出人类可读日志 + 最终 JSON

ACTION="${1:-status}"

# ---------- 检测 ----------
detect() {
	# 两种镜像布局：
	#   A. squashfs 镜像：/overlay 挂在 /dev/loopX（f2fs/ext4），loop 再背靠根分区
	#   B. ext4 镜像：/ 直接挂在 /dev/sdX2（ext4），overlay 在 root 分区内的 upper 目录
	_overlay_loop=$(awk '$2=="/overlay" && $1 ~ /^\/dev\/loop/ {print $1; exit}' /proc/mounts 2>/dev/null)
	_rootdev=$(awk '$2=="/" {print $1}' /proc/mounts 2>/dev/null)

	if [ -n "$_overlay_loop" ]; then
		# --- 模式 A: loop 背靠分区（squashfs 镜像）---
		_partdev=$(losetup -a 2>/dev/null | sed -n "s|^${_overlay_loop}: .*(\(/[^)]*\)).*|\1|p" | head -n1)
		[ -n "$_partdev" ] || { _err="unable to locate backing partition from loop"; return 1; }
		_loop_sz=$(cat "/sys/block/$(basename "$_overlay_loop")/size" 2>/dev/null || echo 0)
		_fstype=$(awk '$2=="/overlay" {print $3}' /proc/mounts 2>/dev/null)
		_fs_base=$_loop_sz
		_mode=loop
	else
		# --- 模式 B: root 直挂分区（ext4 镜像）---
		[ -n "$_rootdev" ] && [ -n "${_rootdev#/dev/loop}" ] && [ -n "${_rootdev#/dev/root}" ] || {
			_err="cannot determine root device"; return 1; }
		_partdev=$_rootdev
		_loop_sz=0
		_fstype=$(awk '$2=="/" {print $3}' /proc/mounts 2>/dev/null)
		_fs_base=0
		_mode=direct
	fi

	# 分区号 与 整个磁盘设备
	_bn=$(basename "$_partdev")                                   # sda2 / nvme0n1p2 / mmcblk0p2
	_part=$(echo "$_bn" | grep -oE '[0-9]+$')                     # 2
	_disk="/dev/$(echo "$_bn" | sed 's/p[0-9][0-9]*$//; s/[0-9][0-9]*$//')"  # /dev/sda / /dev/nvme0n1
	[ -n "$_part" ] && [ -n "$_disk" ] || { _err="cannot parse partition device $_partdev"; return 1; }

	# 扇区大小 (sysfs)
	_disk_sz=$(cat "/sys/block/$(basename "$_disk")/size" 2>/dev/null || echo 0)
	_part_sz=$(cat "/sys/block/$(basename "$_disk")/$_bn/size" 2>/dev/null || echo 0)

	# 预计可扩容空间：磁盘容量 - 当前文件系统容量（模式A=loop，模式B=分区）
	_free_sz=$((_disk_sz - _fs_base))
	[ "$_free_sz" -lt 0 ] && _free_sz=0

	# overlay 文件系统用量 (KB)
	_ovl_size=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $2}')
	_ovl_used=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $3}')
	_ovl_avail=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')

	return 0
}

# ---------- 输出 JSON ----------
print_json() {
	_ok="$1"; _can="$2"; _msg="$3"
	printf '{"ok":%s,"loop":"%s","partdev":"%s","disk":"%s","part":"%s",' \
		"$_ok" "$_overlay_loop" "$_partdev" "$_disk" "$_part"
	printf '"disk_sectors":%s,"part_sectors":%s,"loop_sectors":%s,"free_sectors":%s,' \
		"${_disk_sz:-0}" "${_part_sz:-0}" "${_loop_sz:-0}" "${_free_sz:-0}"
	printf '"ovl_size_kb":%s,"ovl_used_kb":%s,"ovl_avail_kb":%s,' \
		"${_ovl_size:-0}" "${_ovl_used:-0}" "${_ovl_avail:-0}"
	printf '"can_resize":%s,"message":"%s"}\n' "$_can" "$_msg"
}

# ---------- status ----------
status() {
	if ! detect; then
		printf '{"ok":false,"error":"%s"}\n' "$_err"
		return 1
	fi

	# 阈值：可扩空间 < 512MiB 视为"过小"，禁止一键扩容（避免扩完 df 看不出变化）
	_threshold=$((512 * 1024 * 1024 / 512))

	if [ "$_part_sz" -ge "$_disk_sz" ]; then
		_can=false
		_msg="分区已占满整个磁盘，无法扩容（请先在宿主机/磁盘管理中扩大磁盘）"
	elif [ "$_free_sz" -lt "$_threshold" ]; then
		_can=false
		_mb=$((_free_sz * 512 / 1024 / 1024))
		_msg="可扩容空间过小（约 ${_mb}MiB），请先在宿主机/磁盘管理中扩大磁盘"
	else
		_can=true
		_msg="检测到磁盘可用空间，可一键扩容"
	fi
	print_json true "$_can" "$_msg"
}

# ---------- resize ----------
resize() {
	if ! detect; then
		status
		return 1
	fi

	if [ "$_part_sz" -ge "$_disk_sz" ]; then
		printf "==> partition %s already fills disk %s, nothing to do.\n" "$_partdev" "$_disk"
		status
		return 0
	fi

	# 0. 修复 GPT 头：宿主机(如 PVE qm resize)扩容磁盘后，GPT 头的可用空间字段会过期，
	#    parted 报 "Not all of the space available ... appears to be used" 并拒绝扩展。
	#    用 gdisk 专家命令 e（把备份 GPT 重定位到磁盘末尾并重算 LastUsableLBA）修复。
	#    磁盘正常时该操作幂等无害；gdisk 不存在则跳过，交给 parted 直接尝试。
	if [ -x /usr/bin/gdisk ] || [ -x /usr/sbin/gdisk ]; then
		printf "==> fixing GPT header to actual disk size (gdisk e)\n"
		printf 'x\ne\nw\ny\n' | gdisk "$_disk" >/dev/null 2>&1 || true
		partprobe "$_disk" >/dev/null 2>&1 || true
	else
		printf "==> gdisk not installed, skipping GPT fix (install gdisk if parted fails)\n"
	fi

	printf "==> extending partition %s to end of disk (parted -s %s resizepart %s 100%%)\n" \
		"$_partdev" "$_disk" "$_part"
	if ! parted -s "$_disk" resizepart "$_part" 100%; then
		printf "!! parted failed (GPT header may still be stale, or gdisk repair was insufficient). Check partition table state.\n"
		# 失败也必须输出 JSON，否则上层 ucode 解析不到真实错误
		printf '{"ok":false,"error":"parted failed: GPT header may still be stale, or gdisk repair was insufficient"}\n'
		return 1
	fi

	printf "==> refreshing loop device %s (losetup -c)\n" "$_overlay_loop"
	if ! losetup -c "$_overlay_loop" 2>/dev/null; then
		printf "!! losetup refresh failed.\n"
		printf '{"ok":false,"error":"losetup refresh failed"}\n'
		return 1
	fi

	# 文件系统扩容：ext4 在线（resize2fs）；f2fs 无在线扩（需未挂载设备，overlay 卸载不了）
	case "$_mode:$_fstype" in
		direct:ext4|loop:ext4)
			_fsdev="$_partdev"
			[ "$_mode" = "loop" ] && _fsdev="$_overlay_loop"
			printf "==> resizing overlay filesystem online (resize2fs %s)\n" "$_fsdev"
			if ! resize2fs "$_fsdev" 2>&1; then
				printf "!! resize2fs failed.\n"
				printf '{"ok":false,"error":"resize2fs failed"}\n'
				return 1
			fi
			;;
		loop:f2fs)
			printf "!! f2fs overlay cannot be resized online (resize.f2fs requires an unmounted device, and /overlay is the root upperdir).\n"
			printf '{"ok":false,"error":"f2fs overlay cannot be resized online; use the ext4 image instead"}\n'
			return 1
			;;
		*)
			printf "!! unsupported overlay filesystem type: %s (mode %s)\n" "$_fstype" "$_mode"
			printf '{"ok":false,"error":"unsupported overlay filesystem type %s"}\n' "$_fstype"
			return 1
			;;
	esac

	printf "==> resize complete.\n"
	status
}

# ---------- 主入口 ----------
case "$ACTION" in
	status) status ;;
	resize) resize ;;
	*) printf '{"ok":false,"error":"unknown action %s"}\n' "$ACTION"; exit 1 ;;
esac
