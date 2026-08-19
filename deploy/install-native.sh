#!/usr/bin/env bash
# MediaForge 原生一键安装(不装 Docker)。用法见 https://github.com/lipin113/mediaforge/wiki/Native-Linux
# 幂等:重复运行=升级二进制并复用已有密钥;首次运行=自动生成密钥。
set -euo pipefail

IMAGE="crpi-d1fqcfhokj0htk9o.cn-shenzhen.personal.cr.aliyuncs.com/mediafore/mediaforge:latest"
DIR="/opt/mediaforge"
ENVF="$DIR/mediaforge.env"

log(){ printf '\033[36m[MediaForge]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 root 运行(sudo bash ...)"

# 1) 架构
case "$(uname -m)" in
  x86_64|amd64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "不支持的架构: $(uname -m)(仅 amd64/arm64)" ;;
esac
log "架构: $ARCH"

# 2) 包管理器 + 装依赖(skopeo 取二进制;fuse3/rclone 挂载用)
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -q
  apt-get install -y -q skopeo fuse3 rclone tar
elif command -v yum >/dev/null 2>&1; then
  yum install -y -q skopeo fuse3 rclone tar
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y -q skopeo fuse3 rclone tar
else
  die "找不到 apt/yum/dnf,请手动安装 skopeo fuse3 rclone"
fi
log "依赖已装 (skopeo/fuse3/rclone)"

# 3) 取二进制 + 配置
mkdir -p "$DIR"
rm -rf "$DIR/_img"
log "从镜像仓库取二进制(架构 $ARCH)..."
skopeo copy --override-arch "$ARCH" --override-os linux "docker://$IMAGE" "oci:$DIR/_img:latest"
for b in "$DIR"/_img/blobs/sha256/*; do
  tar tzf "$b" 2>/dev/null | grep -q '^app/fsdockerd$'    && tar xzf "$b" -C "$DIR" app/fsdockerd || true
  tar tzf "$b" 2>/dev/null | grep -q 'app/configs/config' && tar xzf "$b" -C "$DIR" app/configs/config.example.json || true
done
[ -f "$DIR/app/fsdockerd" ] || die "未能从镜像取出二进制"
systemctl stop mediaforge 2>/dev/null || true
mv -f "$DIR/app/fsdockerd" "$DIR/fsdockerd"
mkdir -p "$DIR/configs"
mv -f "$DIR/app/configs/config.example.json" "$DIR/configs/config.json"
rm -rf "$DIR/_img" "$DIR/app"
chmod +x "$DIR/fsdockerd"
mkdir -p "$DIR/data" "$DIR/media" "$DIR/strm"
log "二进制就位: $DIR/fsdockerd"

# 4) 密钥:首次生成随机,已存在则复用(MASTER_KEY 不能变)
gen(){ head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
if [ -f "$ENVF" ]; then
  log "复用已有密钥 ($ENVF)"
else
  log "首次安装,生成随机密钥..."
  cat > "$ENVF" <<EOF
FSM_MASTER_KEY=$(gen)
FSM_SESSION_SECRET=$(gen)
FSM_PROXY_TOKEN=$(gen)
FSM_DATA_ROOT=$DIR/data
FSM_MOUNT_CACHE_DIR=$DIR/data/cache
FSM_HTTP_LISTEN=:7860
FSM_PROXY_LISTEN=:17860
FSM_MOUNT_HOST_PATH_PREFIX=$DIR/media
FSM_MOUNT_RUNTIME_PATH_PREFIX=$DIR/media
EOF
  chmod 600 "$ENVF"
fi

# 5) systemd 服务
cat > /etc/systemd/system/mediaforge.service <<EOF
[Unit]
Description=MediaForge
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$DIR
EnvironmentFile=$ENVF
ExecStart=$DIR/fsdockerd -config $DIR/configs/config.json
Restart=always
RestartSec=5
DeviceAllow=/dev/fuse rw
CapabilityBoundingSet=CAP_SYS_ADMIN CAP_SETUID CAP_SETGID

[Install]
WantedBy=multi-user.target
EOF

# 6) 启动
systemctl daemon-reload
systemctl enable --now mediaforge
sleep 4
if systemctl is-active --quiet mediaforge; then
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  log "✅ 安装完成!已启动并设为开机自启。"
  log "   访问管理界面: http://${IP:-服务器IP}:7860"
  log "   查看日志: journalctl -u mediaforge -f"
  log "   密钥文件(请备份): $ENVF"
else
  die "服务启动失败,查看: journalctl -u mediaforge -n 50 --no-pager"
fi
