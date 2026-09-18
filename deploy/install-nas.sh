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

# 2) 确定数据根目录。
#    优先用户手动指定 MF_ROOT(兜底任何 NAS/任何版本);否则自动探测各家 docker 共享文件夹。
#    候选覆盖:群晖/绿联(/volume1)、铁威马TOS6(/Volume1/User)、铁威马其它(/Volume1)、飞牛(/vol1/1000)、威联通(/share)。
BASE=""
# 手动指定路径:位置参数 $1 优先(curl ... | sudo bash -s -- /你的docker路径),其次 MF_ROOT 环境变量
MANUAL="${1:-${MF_ROOT:-}}"
if [ -n "$MANUAL" ]; then
  [ -d "$MANUAL" ] || die "你指定的路径 $MANUAL 不存在,请检查(要填 File Station 里能看到的共享文件夹真实路径)。"
  BASE="$MANUAL"
  log "使用手动指定路径: $BASE"
else
  CANDS="/volume1/docker /Volume1/User/docker /Volume1/docker /vol1/1000/docker /share/Container /share/Docker /volume2/docker /Volume2/User/docker"
  # 先找已存在的 docker 目录
  for c in $CANDS; do
    if [ -d "$c" ]; then BASE="$c"; break; fi
  done
  # 没有现成的,就找父目录(共享文件夹根)存在的
  if [ -z "$BASE" ]; then
    for c in $CANDS; do
      if [ -d "$(dirname "$c")" ]; then BASE="$c"; break; fi
    done
  fi
  [ -n "$BASE" ] || die "未能自动识别你的 NAS 数据卷。请手动指定路径重试(换成你 File Station 里能看到的共享文件夹真实路径):
    curl -fsSL https://cdn.jsdelivr.net/gh/lipin113/mediaforge@main/deploy/install-nas.sh | sudo bash -s -- /你的共享文件夹/docker"
fi
ROOT="$BASE/mediaforge"
MEDIA="$ROOT/media"; STRM="$ROOT/strm"; DATA="$ROOT/data"
log "数据目录: $ROOT (File Station 里可见)"
mkdir -p "$MEDIA" "$STRM" "$DATA"
# 密钥文件候选位置:密钥仅通过 docker run -e 传入容器,该文件只是宿主机侧持久化以便重装复用,
# 放哪都行只要能写。飞牛(fnOS)等 NAS 的共享文件夹根目录可能拒绝 root 建普通文件(EPERM),
# 故备多个候选,后面按"已存在优先、否则第一个可写"来选,绕开该坑。
ENV_CANDS="$ROOT/mediaforge.env $DATA/mediaforge.env /usr/local/etc/mediaforge.env /root/.mediaforge.env /etc/mediaforge.env"

# 3) 挂载传播(FUSE 挂载在宿主机可见需要 rshared)
for t in "$MEDIA" "$STRM"; do
  grep -F " $t " /proc/self/mountinfo >/dev/null 2>&1 || mount --bind "$t" "$t"
  mount --make-rshared "$t"
done
log "挂载传播已就绪"

# 4) 密钥:首次生成随机,已存在则复用
gen(){ head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

# 4.1) 先在所有候选位置找已有密钥文件复用(重装场景:密钥必须保持不变,否则旧数据解不开)
ENVF=""
for c in $ENV_CANDS; do
  if [ -f "$c" ]; then ENVF="$c"; break; fi
done
if [ -n "$ENVF" ]; then
  log "复用已有密钥 ($ENVF)"
  # shellcheck disable=SC1090
  . "$ENVF"
else
  # 4.2) 首次安装:挑第一个"真能写"的候选位置(试写探测)。飞牛共享文件夹根拒建文件时自动跳到下一个。
  log "首次安装,生成随机密钥..."
  chattr -i "$ROOT" 2>/dev/null || true   # 若共享文件夹被加了 immutable 属性,先尝试解除
  ENVF=""
  for c in $ENV_CANDS; do
    d=$(dirname "$c")
    mkdir -p "$d" 2>/dev/null || continue
    if ( : > "$c" ) 2>/dev/null; then ENVF="$c"; break; fi   # 试写成功即选它
  done
  [ -n "$ENVF" ] || die "找不到可写位置保存密钥文件(已试:$ENV_CANDS)。
    你的 NAS 可能限制了这些目录的写入。请手动指定一个能写的共享文件夹重装:
    curl -fsSL https://cdn.jsdelivr.net/gh/lipin113/mediaforge@main/deploy/install-nas.sh | sudo bash -s -- /你能写的共享文件夹/docker"
  FSM_MASTER_KEY=$(gen); FSM_SESSION_SECRET=$(gen); FSM_PROXY_TOKEN=$(gen)
  # 密钥落地失败绝不继续(否则会留个缺密钥的容器反复重启)
  if ! cat > "$ENVF" <<EOF
FSM_MASTER_KEY=$FSM_MASTER_KEY
FSM_SESSION_SECRET=$FSM_SESSION_SECRET
FSM_PROXY_TOKEN=$FSM_PROXY_TOKEN
EOF
  then
    die "密钥文件写入失败 ($ENVF)。请换一个能写的共享文件夹重装(见上条命令的 -s -- 用法)。"
  fi
  chmod 600 "$ENVF" 2>/dev/null || true
  log "密钥已保存: $ENVF"
fi

# 4.5) 端口占用检测(7860/17860 被别的程序占会导致容器反复重启)
# ★grep -c 数到0会返回失败退出码,set -e 下必须用 || true 兜住,否则脚本静默退出(飞牛干净机踩过)
portbusy(){ { ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null; } | grep -c ":$1 " || true; }
for port in 7860 17860; do
  busy=$(portbusy "$port")
  # 排除本程序自己占用(重装场景):先停掉旧的同名容器再判断
  if [ "${busy:-0}" -gt 0 ]; then
    "$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
    sleep 1
    busy=$(portbusy "$port")
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
  -e FSM_STRM_HOST_PATH="$STRM" \
  -e FSM_STRM_CONTAINER_PATH=/strm \
  -e FSM_LOCALFS_BROWSE_ROOT=/hostfs \
  -v "$DATA":/app/data \
  -v "$MEDIA":/mnt/media:rshared \
  -v "$STRM":/strm \
  -v /:/hostfs:ro \
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
