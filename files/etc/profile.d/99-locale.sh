# 等价于初始化文档里的: echo 'export LC_ALL=C.UTF-8' >> /etc/profile
# 官方 /etc/profile 会 source /etc/profile.d/*.sh，因此无需覆盖整个 profile
#（覆盖 profile 会破坏 base-files 构建时替换的 %PATH% 占位符）。
export LC_ALL=C.UTF-8
