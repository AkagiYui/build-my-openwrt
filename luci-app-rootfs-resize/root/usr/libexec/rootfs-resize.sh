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
	# 1. overlay 的 loop 设备 (/overlay 挂在 /dev/loopX)
	_overlay_loop=$(awk '$2=="/overlay" && $1 ~ /^\/dev\/loop/ {print $1; exit}' /proc/mounts 2>/dev/null)
	[ -n "$_overlay_loop" ] || { _err="找不到 overlay 的 loop 设备"; return 1; }

	# 2. loop 的 backing 分区 (/dev/loop0: [..]:.. (/sda2), offset ..)
	_partdev=$(losetup -a 2>/dev/null | sed -n "s|^${_overlay_loop}: .*(\(/[^)]*\)).*|\1|p" | head -n1)
	[ -n "$_partdev" ] || { _err="无法从 loop 定位 backing 分区"; return 1; }

	# 3. 分区号 与 整个磁盘设备
	_bn=$(basename "$_partdev")                                   # sda2 / nvme0n1p2 / mmcblk0p2
	_part=$(echo "$_bn" | grep -oE '[0-9]+$')                     # 2
	_disk="/dev/$(echo "$_bn" | sed 's/p[0-9][0-9]*$//; s/[0-9][0-9]*$//')"  # /dev/sda / /dev/nvme0n1
	[ -n "$_part" ] && [ -n "$_disk" ] || { _err="无法解析分区设备 $_partdev"; return 1; }

	# 4. 扇区大小 (sysfs)
	_disk_sz=$(cat "/sys/block/$(basename "$_disk")/size" 2>/dev/null || echo 0)
	_part_sz=$(cat "/sys/block/$(basename "$_disk")/$_bn/size" 2>/dev/null || echo 0)
	_loop_sz=$(cat "/sys/block/$(basename "$_overlay_loop")/size" 2>/dev/null || echo 0)

	# 5. overlay 文件系统用量 (KB)
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
	printf '"disk_sectors":%s,"part_sectors":%s,"loop_sectors":%s,' \
		"${_disk_sz:-0}" "${_part_sz:-0}" "${_loop_sz:-0}"
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
	if [ "$_part_sz" -lt "$_disk_sz" ]; then
		_can=true
		_msg="磁盘存在可用空间，可一键扩容"
	else
		_can=false
		_msg="分区已占满整个磁盘，无法扩容（请先在宿主机/磁盘管理中扩大磁盘）"
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
		printf "==> 分区 %s 已占满磁盘 %s，无需扩容。\n" "$_partdev" "$_disk"
		status
		return 0
	fi

	printf "==> 扩大分区 %s 到磁盘末尾 (parted -s %s resizepart %s 100%%)\n" \
		"$_partdev" "$_disk" "$_part"
	if ! parted -s "$_disk" resizepart "$_part" 100%; then
		printf "!! parted 失败，请确认分区表状态。\n"
		return 1
	fi

	printf "==> 刷新 loop 设备 %s (losetup -c)\n" "$_overlay_loop"
	if ! losetup -c "$_overlay_loop"; then
		printf "!! losetup 刷新失败。\n"
		return 1
	fi

	printf "==> 在线扩容 overlay 文件系统 (resize2fs %s)\n" "$_overlay_loop"
	if ! resize2fs "$_overlay_loop"; then
		printf "!! resize2fs 失败。\n"
		return 1
	fi

	printf "==> 扩容完成。\n"
	status
}

# ---------- 主入口 ----------
case "$ACTION" in
	status) status ;;
	resize) resize ;;
	*) printf '{"ok":false,"error":"unknown action %s"}\n' "$ACTION"; exit 1 ;;
esac
