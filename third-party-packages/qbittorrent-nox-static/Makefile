include $(TOPDIR)/rules.mk

PKG_NAME:=qbittorrent-nox-static
PKG_VERSION:=5.0.5
PKG_RELEASE:=1

PKG_LICENSE:=GPL-2.0-or-later
PKG_MAINTAINER:=AkagiYui <dev@example.com>

include $(INCLUDE_DIR)/package.mk

# 官方静态二进制来自 userdocs/qbittorrent-nox-static，由 CI 下载后塞进 files/ 再打包。
# PROVIDES:=qbittorrent 让 luci-app-qbittorrent 的 LUCI_DEPENDS:=+qbittorrent 得到满足。
# 纯文件包（无源码）：跳过 configure/compile，仅执行 install 段。

define Package/$(PKG_NAME)
	SECTION:=net
	CATEGORY:=Network
	SUBMENU:=BitTorrent
	TITLE:=qBittorrent nox (static binary from userdocs, no compile)
	PROVIDES:=qbittorrent
	PKGARCH:=all
	URL:=https://github.com/userdocs/qbittorrent-nox-static
endef

define Package/$(PKG_NAME)/description
	Prebuilt static qbittorrent-nox binary.
	Provides the qbittorrent package so luci-app-qbittorrent can depend on it.
	WebUI: port 8080, default credentials admin/adminadmin (configurable via uci).
endef

define Build/Prepare
endef

define Build/Configure
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./files/usr/bin/qbittorrent-nox $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/etc/init.d/qbittorrent $(1)/etc/init.d/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./files/etc/config/qbittorrent $(1)/etc/config/
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
