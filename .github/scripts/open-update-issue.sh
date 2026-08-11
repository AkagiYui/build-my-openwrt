#!/usr/bin/env bash
# 打开"官方有新版本"的提醒 Issue（如已有同版本 open issue 则跳过）。
# 环境变量: GH_TOKEN(gh 自动), LATEST, CURRENT
set -euo pipefail

: "${LATEST:?LATEST env required}"
: "${CURRENT:?CURRENT env required}"

if [ "$(gh issue list --state open --search "v${LATEST} available in:title" --json number --jq 'length')" -ge 1 ]; then
  echo "Open issue for v${LATEST} already exists, skipping"
  exit 0
fi

cat > /tmp/issue-body.md <<EOF
官方发布了新版本 **OpenWrt v${LATEST}**（当前仓库默认构建 v${CURRENT}）。

- 发布说明: https://openwrt.org/releases/${LATEST%.*}/notes-${LATEST}
- 下载目录: https://downloads.openwrt.org/releases/${LATEST}/targets/x86/64/

**升级步骤：**
1. Actions → *Build OpenWrt x86_64 combined-efi* → Run workflow，Version 填 \`${LATEST}\`
2. 下载产物确认 \`openwrt-${LATEST}-x86-64-generic-squashfs-combined-efi.img.gz\`
3. 复核 PACKAGES 各包名在新版本源里仍存在（重点 \`block-mount\` 在 targets feed、\`resize2fs\` 为独立包）
4. \`files/\` 配置点版本一般无需改动；大版本升级前先 diff 官方默认值

内核与 kmods 自动配套，无需手动处理。
EOF

gh issue create \
  --title "OpenWrt upstream: v${LATEST} available (current: v${CURRENT})" \
  --body-file /tmp/issue-body.md
