# luci-app-rootfs-resize
# 纯 shell + ucode + JS 的 LuCI 插件：一键扩容 overlay 所在分区与文件系统
# 抽象自 PVE 部署流程: parted resizepart -> losetup -c -> resize2fs（在线，无需重启）
#
# 纯 Makefile 写法（不依赖 feeds/luci/luci.mk），可在官方 SDK 中直接编译
# 产物为 .apk（OpenWrt 25.12 apk 体系，架构无关 all）
# i18n: po/ 是源码，CI 用宿主持编译的 po2lmo 生成 i18n/*.lmo 后再打包（.lmo 不入 git）

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-rootfs-resize
PKG_VERSION:=1.1.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=AkagiYui <dev@example.com>

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	TITLE:=One-click rootfs/overlay resize for x86/arm (PVE workflow)
	DEPENDS:=+luci-base +parted +losetup +resize2fs +f2fs-tools +block-mount +gdisk
	PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
	Detect and resize the partition and filesystem backing /overlay,
	abstracted from the PVE deployment workflow:
	parted resizepart -> losetup -c -> resize2fs (online, no reboot).
endef

# 纯文件包（无源码）：跳过 configure/compile，仅执行 install 段
define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/libexec
	$(INSTALL_BIN) ./root/usr/libexec/rootfs-resize.sh $(1)/usr/libexec/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/ucode
	$(INSTALL_DATA) ./root/usr/share/rpcd/ucode/rootfs-resize.uc $(1)/usr/share/rpcd/ucode/

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-rootfs-resize.json $(1)/usr/share/rpcd/acl.d/

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-rootfs-resize.json $(1)/usr/share/luci/menu.d/

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/rootfsresize
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/rootfsresize/overview.js $(1)/www/luci-static/resources/view/rootfsresize/

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_DATA) ./root/etc/uci-defaults/50-rootfs-resize $(1)/etc/uci-defaults/

	if [ -d ./root/usr/lib/lua/luci/i18n ]; then \
		$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n; \
		$(CP) ./root/usr/lib/lua/luci/i18n/* $(1)/usr/lib/lua/luci/i18n/; \
	fi
endef

define Package/$(PKG_NAME)/postinst
	[ -n "$${IPKG_INSTROOT}" ] || { \
		rm -f /tmp/luci-indexcache.* ; \
		rm -rf /tmp/luci-modulecache/ ; \
		/etc/init.d/rpcd reload 2>/dev/null ; \
		exit 0 ; \
	}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
