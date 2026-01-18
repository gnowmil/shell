#!/bin/bash

# ==========================================================
# 📋 参数设置区 (所有配置在此集中管理)
# ==========================================================
# 1. 镜像源 (留空则保持默认)
MIRROR_URL="mirrors.ustc.edu.cn" 
PROTOCOL="https"

# 2. 基础软件包列表 (一次性安装)
# 包含：基础工具、语言包支持、字体支持、网络工具
BASIC_PKGS="curl wget git locales"

# 3. 时区
TIMEZONE="Asia/Hong_Kong"

# 4. NTP 服务器
NTP_SERVER="10.0.0.1"

# 5. 语言环境
LOCALES_TO_GENERATE=("en_US.UTF-8" "zh_CN.UTF-8" "zh_HK.UTF-8")
DEFAULT_LANG="en_US.UTF-8"
# ==========================================================

set -e

# 权限与版本检查
if [ "$EUID" -ne 0 ]; then echo "错误: 请以 root 运行"; exit 1; fi
VERSION_ID=$(grep "VERSION_ID" /etc/os-release | cut -d'=' -f2 | tr -d '"')
CODENAME=$(grep "VERSION_CODENAME" /etc/os-release | cut -d'=' -f2 | tr -d '"')

echo ">>> [阶段 1/3] 配置 APT 软件源 ($PROTOCOL 协议)..."
# ----------------------------------------------------------
# 第一性原理：先修改协议和地址，再进行更新
if [ -n "$MIRROR_URL" ]; then
    if [ "$VERSION_ID" -ge "13" ]; then
    # --- Debian 13+ (DEB822 格式重写) ---
    TARGET_FILE="/etc/apt/sources.list.d/debian.sources"
    echo "正在重写 DEB822 源配置文件: $TARGET_FILE"
    
    cat > "$TARGET_FILE" <<EOF
# 主仓库与更新仓库
Types: deb
URIs: $PROTOCOL://$MIRROR_URL/debian/
Suites: $CODENAME ${CODENAME}-updates
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg

# 安全更新仓库
Types: deb
URIs: $PROTOCOL://$MIRROR_URL/debian-security
Suites: ${CODENAME}-security
Components: main
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
EOF
    else
        # --- Debian 11/12 (传统格式) ---
        TARGET_FILE="/etc/apt/sources.list"
        # 1. 替换地址
        sed -i "s|deb.debian.org|$MIRROR_URL|g" "$TARGET_FILE"
        sed -i "s|security.debian.org|$MIRROR_URL/debian-security|g" "$TARGET_FILE"
        # 2. 统一将 http 替换为 https
        sed -i "s|http://|$PROTOCOL://|g" "$TARGET_FILE"
        echo "已更新传统格式源为 $PROTOCOL"
    fi
else
    echo "保持默认源不变，仅尝试强制升级协议..."
    sed -i "s|http://|$PROTOCOL://|g" /etc/apt/sources.list* 2>/dev/null || true
fi


echo ">>> [阶段 2/3] 一次性系统更新与基础包安装..."
# ----------------------------------------------------------
# 合并命令，减少磁盘 I/O 和 metadata 刷新次数
apt update && apt upgrade -y && apt install -y $BASIC_PKGS


echo ">>> [阶段 3/3] 环境设置与系统优化..."
# ----------------------------------------------------------
# 1. 时区设置
if [ -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    echo "$TIMEZONE" > /etc/timezone
    echo "时区已设置为 $TIMEZONE"
fi

# 2. 语言环境 (解决 SSH 登录警告)
for loc in "${LOCALES_TO_GENERATE[@]}"; do
    sed -i "/^# $loc/s/^# //" /etc/locale.gen
done
locale-gen

cat > /etc/default/locale <<EOF
LANG=$DEFAULT_LANG
LC_ALL=$DEFAULT_LANG
LANGUAGE=$DEFAULT_LANG
EOF
export LANG=$DEFAULT_LANG
export LC_ALL=$DEFAULT_LANG
echo "Locale 已生成并设置为 $DEFAULT_LANG"

# 3. SSHD 配置优化 (防止客户端 Locale 污染)
if [ -f /etc/ssh/sshd_config ]; then
    sed -i 's/^AcceptEnv/#AcceptEnv/' /etc/ssh/sshd_config
fi

# 4. 最终清理
apt autoremove -y && apt clean
truncate -s 0 /etc/machine-id

echo "-----------------------------------------------"
echo "✅ 所有任务完成！"
echo "源地址: $MIRROR_URL"
echo "安装包: $BASIC_PKGS"
echo "时区: $TIMEZONE"
echo "-----------------------------------------------"
