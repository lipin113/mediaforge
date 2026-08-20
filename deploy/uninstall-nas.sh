#!/usr/bin/env bash
# MediaForge NAS 一键卸载(Docker 版,自动适配群晖/飞牛/威联通/绿联/铁威马)
# 用法:
#   curl -fsSL <地址>/uninstall-nas.sh | sudo bash                 # 停容器+卸载残留挂载(保留数据目录)
#   curl -fsSL <地址>/uninstall-nas.sh | sudo bash -s -- --purge   # 顺带删除整个数据目录(含密钥/缓存)
#   curl -fsSL <地址>/uninstall-nas.sh | sudo bash -s -- /你的docker路径          # 手动指定路径
#   curl -fsSL <地址>/uninstall-nas.sh | sudo bash -s -- /你的docker路径 --purge  # 手动路径+删目录
#
# 为什么需要这个脚本:安装时为了让网盘 FUSE 挂载在宿主机可见,对 media/strm 目录做了
# `mount --bind` + `--make-rshared`。这层挂载建在宿主机上、不归容器生命周期管——所以
# 「停了 Docker、删了容器」后,这两个目录仍是「活的挂载点」,File Station 里删它会报
# 「删除失败,请检查权限」(其实不是权限,是挂载点被占用)。本脚本把这些挂载卸载干净。
set -euo pipefail

NAME="mediaforge"
log(){ printf '\033[36m[MediaForge]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[提示]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[错误]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "请用 root 运行(sudo bash ...)"

# --- 解析参数:--purge=删目录;其余非 flag 参数=手动指定 docker 路径 ---
PURGE=0
MANUAL=""
for a in "$@"; do
  case "$a" in
    --purge) PURGE=1 ;;
    -*) die "未知参数: $a" ;;
    *) MANUAL="$a" ;;
  esac
done

# --- 找 docker 命令(群晖在 /usr/local/bin/docker;其它在 PATH)---
DOCKER=""
for d in docker /usr/local/bin/docker /usr/bin/docker /volume1/@appstore/ContainerManager/usr/bin/docker; do
  if command -v "$d" >/dev/null 2>&1 || [ -x "$d" ]; then DOCKER="$d"; break; fi
done

# --- 1) 停止并删除容器(先停,才能触发 rclone 卸载 FUSE)---
if [ -n "$DOCKER" ]; then
  if "$DOCKER" ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$NAME"; then
    log "停止并删除容器 $NAME ..."
    "$DOCKER" rm -f "$NAME" >/dev/null 2>&1 || true
    sleep 2
  else
    log "未发现名为 $NAME 的容器(可能已删除),继续清理挂载残留。"
  fi
else
  warn "未找到 docker 命令,跳过删容器,直接清理挂载残留。"
fi

# --- 2) 确定数据根目录(与安装脚本同一套探测逻辑)---
BASE=""
if [ -n "$MANUAL" ]; then
  [ -d "$MANUAL" ] || die "你指定的路径 $MANUAL 不存在。"
  BASE="$MANUAL"
else
  CANDS="/volume1/docker /Volume1/User/docker /Volume1/docker /vol1/1000/docker /share/Container /share/Docker /volume2/docker /Volume2/User/docker"
  for c in $CANDS; do
    if [ -d "$c/mediaforge" ]; then BASE="$c"; break; fi
  done
fi

if [ -z "$BASE" ]; then
  warn "未自动定位到 mediaforge 数据目录。若挂载仍未清干净,请手动指定路径重跑:"
  warn "  curl -fsSL <地址>/uninstall-nas.sh | sudo bash -s -- /你的docker路径"
fi

ROOT=""
[ -n "$BASE" ] && ROOT="$BASE/mediaforge"
[ -n "$ROOT" ] && log "数据目录: $ROOT"

# --- 3) 卸载挂载残留 ---
# 兜底:即便没定位到 ROOT,也扫 mountinfo 里所有含 /mediaforge/ 的挂载点全卸掉。
unmount_one(){
  # $1 = 挂载点路径。先普通卸,忙则 lazy 卸(-l),再不行 -f。
  local mp="$1"
  umount "$mp" 2>/dev/null && { log "已卸载: $mp"; return; }
  umount -l "$mp" 2>/dev/null && { log "已卸载(延迟): $mp"; return; }
  umount -f "$mp" 2>/dev/null && { log "已卸载(强制): $mp"; return; }
  warn "卸载失败(可能已不是挂载点): $mp"
}

# 3a) 先卸载 media 下面的网盘 FUSE 子挂载(深的先卸)——按挂载点路径长度倒序,先子后父。
collect_mounts(){
  # 输出所有匹配 /mediaforge/ 的挂载点,按路径长度降序(最深的在前)
  awk '{print $5}' /proc/self/mountinfo 2>/dev/null \
    | grep -E '/mediaforge/' \
    | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2- | uniq
}

if [ -n "$ROOT" ]; then
  # 优先只处理本 ROOT 下的挂载,避免误伤别的
  MOUNTS=$(collect_mounts | grep -F "$ROOT/" || true)
else
  MOUNTS=$(collect_mounts || true)
fi

if [ -n "$MOUNTS" ]; then
  log "发现以下挂载残留,开始逐个卸载(先子挂载后父挂载):"
  printf '%s\n' "$MOUNTS"
  # 多轮尝试:FUSE 子挂载卸完,父 bind 挂载才卸得动
  for _round in 1 2 3; do
    LEFT=""
    if [ -n "$ROOT" ]; then LEFT=$(collect_mounts | grep -F "$ROOT/" || true); else LEFT=$(collect_mounts || true); fi
    [ -z "$LEFT" ] && break
    while IFS= read -r mp; do
      [ -n "$mp" ] && unmount_one "$mp"
    done <<< "$LEFT"
    sleep 1
  done
else
  log "没有发现挂载残留(已经是干净状态)。"
fi

# --- 4) 验证 ---
REMAIN=""
if [ -n "$ROOT" ]; then REMAIN=$(collect_mounts | grep -F "$ROOT/" || true); else REMAIN=$(collect_mounts || true); fi
if [ -n "$REMAIN" ]; then
  warn "仍有未卸载的挂载点(可能被其它进程占用):"
  printf '%s\n' "$REMAIN"
  warn "请确认没有别的程序在用它,然后重跑本脚本;或重启 NAS 后再删目录。"
else
  log "✅ 挂载残留已全部清除。"
fi

# --- 5) 可选:删除整个数据目录 ---
if [ "$PURGE" = 1 ]; then
  if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
    warn "未定位到数据目录,跳过删除。"
  elif [ -n "$REMAIN" ]; then
    die "仍有挂载未卸干净,为安全起见不删除目录。请先清干净挂载再重试。"
  else
    warn "即将删除整个数据目录(含密钥 mediaforge.env + 加密缓存 data/): $ROOT"
    rm -rf "$ROOT" && log "✅ 已删除 $ROOT" || die "删除失败: $ROOT"
  fi
else
  if [ -n "$ROOT" ] && [ -d "$ROOT" ] && [ -z "$REMAIN" ]; then
    log "数据目录已保留: $ROOT"
    log "现在可以在 File Station 里正常删除它了;或重跑本脚本加 --purge 由脚本删除。"
  fi
fi

log "卸载流程结束。"

