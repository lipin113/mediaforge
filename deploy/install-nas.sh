#!/usr/bin/env bash
# MediaForge NAS 一键安装(Docker 版,自动适配群晖/飞牛/威联通/绿联/铁威马)
# 用法: curl -fsSL <地址>/install-nas.sh | sudo bash
# 幂等:重复运行=拉最新镜像重建容器并复用已有密钥。
set -euo pipefail

IMAGE="crpi-d1fqcfhokj0htk9o.cn-shenzhen.personal.cr.aliyuncs.com/mediafore/mediaforge:latest"
NAME="mediaforge"

log(){ printf '\033[36m[MediaForge]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 root 运行(sudo bash ...)"

# 1) 找 docker 命令(群晖在 /usr/local/bin/docker;其它在 PATH)
DOCKER=""
for d in docker /usr/local/bin/docker /usr/bin/docker /volume1/@appstore/ContainerManager/usr/bin/docker; do
  if command -v "$d" >/dev/null 2>&1 || [ -x "$d" ]; then DOCKER="$d"; break; fi
done
[ -n "$DOCKER" ] || die "未找到 docker。请先在 NAS 套件中心安装 Container Manager / Container Station / Docker。"
log "docker: $DOCKER"

# 2) 探测 NAS 的 docker 共享文件夹(界面可见)。找到第一个存在的父目录。
BASE=""
for c in /volume1/docker /vol1/1000/docker /share/Container /share/Docker /volume2/docker; do
  parent="$(dirname "$c")"
  if [ -d "$parent" ]; then BASE="$c"; break; fi
done
[ -n "$BASE" ] || die "未找到 NAS 数据卷(试过 /volume1 /vol1/1000 /share 等)。请把你的 docker 共享文件夹路径告诉作者。"
ROOT="$BASE/mediaforge"
MEDIA="$ROOT/media"; STRM="$ROOT/strm"; DATA="$ROOT/data"
ENVF="$ROOT/mediaforge.env"
log "数据目录: $ROOT (File Station 里可见)"
mkdir -p "$MEDIA" "$STRM" "$DATA"

# 3) 挂载传播(FUSE 挂载在宿主机可见需要 rshared)
for t in "$MEDIA" "$STRM"; do
  grep -F " $t " /proc/self/mountinfo >/dev/null 2>&1 || mount --bind "$t" "$t"
  mount --make-rshared "$t"
done
log "挂载传播已就绪"

# 4) 密钥:首次生成随机,已存在则复用
gen(){ head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }
if [ -f "$ENVF" ]; then
  log "复用已有密钥 ($ENVF)"
  # shellcheck disable=SC1090
  . "$ENVF"
else
  log "首次安装,生成随机密钥..."
  FSM_MASTER_KEY=$(gen); FSM_SESSION_SECRET=$(gen); FSM_PROXY_TOKEN=$(gen)
  cat > "$ENVF" <<EOF
FSM_MASTER_KEY=$FSM_MASTER_KEY
FSM_SESSION_SECRET=$FSM_SESSION_SECRET
FSM_PROXY_TOKEN=$FSM_PROXY_TOKEN
EOF
  chmod 600 "$ENVF"
fi

# 4.5) 端口占用检测(7860/17860 被别的程序占会导致容器反复重启)
for port in 7860 17860; do
  if command -v ss >/dev/null 2>&1; then busy=$(ss -ltn "sport = :$port" 2>/dev/null | grep -c ":$port")
  else busy=$(netstat -ltn 2>/dev/null | grep -c ":$port ")||true; fi
  # 排除本程序自己占用(重装场景):先停掉旧的同名容器再判断
  if [ "${busy:-0}" -gt 0 ]; then
    "$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
    sleep 1
    if command -v ss >/dev/null 2>&1; then busy=$(ss -ltn "sport = :$port" 2>/dev/null | grep -c ":$port")
    else busy=$(netstat -ltn 2>/dev/null | grep -c ":$port ")||true; fi
    [ "${busy:-0}" -gt 0 ] && die "端口 $port 已被其它程序占用,请先释放它(或停掉占用它的容器/服务)再重试。"
  fi
done

# 5) 拉镜像 + 重建容器
log "拉取镜像(首次约 70MB)..."
"$DOCKER" pull "$IMAGE"
"$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
log "启动容器..."
"$DOCKER" run -d --name "$NAME" \
  --network host --privileged --init \
  --cap-add SYS_ADMIN --device /dev/fuse:/dev/fuse \
  --security-opt apparmor:unconfined \
  --restart unless-stopped \
  -e FSM_MASTER_KEY="$FSM_MASTER_KEY" \
  -e FSM_SESSION_SECRET="$FSM_SESSION_SECRET" \
  -e FSM_PROXY_TOKEN="$FSM_PROXY_TOKEN" \
  -e FSM_MOUNT_HOST_PATH_PREFIX="$MEDIA" \
  -e FSM_MOUNT_RUNTIME_PATH_PREFIX=/mnt/media \
  -v "$DATA":/app/data \
  -v "$MEDIA":/mnt/media:rshared \
  -v "$STRM":/strm \
  "$IMAGE"

# 6) 冒烟
sleep 5
if "$DOCKER" ps --filter "name=^${NAME}$" --format '{{.Names}}' | grep -q "$NAME"; then
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')
  log "✅ 安装完成!已启动并设为开机自启。"
  log "   访问管理界面: http://${IP:-你的NAS IP}:7860"
  log "   媒体目录: $MEDIA"
  log "   STRM 目录: $STRM"
  log "   密钥文件(请备份): $ENVF"
  log "   看日志: $DOCKER logs -f $NAME"
else
  die "容器未起来,查看: $DOCKER logs $NAME"
fi
