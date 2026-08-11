# luci-app-rootfs-resize
# 纯 shell + ucode + JS 的 LuCI 插件：一键扩容 overlay 所在分区与文件系统
# 纯 Makefile 写法（不依赖 feeds/luci/luci.mk），可在官方 SDK 中直接编译
# 产物为 .apk（OpenWrt 25.12 apk 体系，架构无关 all）

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-rootfs-resize
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=AkagiYui <dev@example.com>

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	SECTION:=luci
	CATEGORY:=LuCI
	TITLE:=One-click rootfs/overlay resize for x86/arm (PVE workflow)
	DEPENDS:=+luci-base +parted +losetup +resize2fs +block-mount
	PKGARCH:=all
endef

define Package/$(PKG_NAME)/description
	Detect and resize the partition and filesystem backing /overlay,
	abstracted from the PVE deployment workflow:
	parted resizepart -> losetup -c -> resize2fs (online, no reboot).
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
