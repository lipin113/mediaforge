<div align="center">

<img src="assets/logo.svg" alt="MediaForge" width="120" height="120">

# MediaForge

**多网盘 · 全自动媒体整理引擎**

新媒体一落地，自动按 TMDB 规范重命名、生成全播放器通用 STRM，联动 Emby 等媒体服务器自动刮削入库 —— 全程免手动。

<br>

[![平台](https://img.shields.io/badge/平台-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android%20%7C%20NAS%20%7C%20Docker-2b7bba)](#)
[![播放器](https://img.shields.io/badge/播放器-Emby%20%7C%20Jellyfin%20%7C%20Plex%20%7C%20Infuse%20%7C%20VLC-4c9a2a)](#)
[![部署](https://img.shields.io/badge/部署-Docker%20Compose-2496ed)](#)
[![文档](https://img.shields.io/badge/文档-Wiki-8957e5)](https://github.com/lipin113/mediaforge/wiki)

[📖 完整文档 Wiki](https://github.com/lipin113/mediaforge/wiki) · [🚀 快速上手](https://github.com/lipin113/mediaforge/wiki/Quick-Start) · [💬 联系与支持](https://github.com/lipin113/mediaforge/wiki/Support)

> 📱 手机 GitHub App 看不到 Wiki（App 不支持 Wiki 功能），请用手机**浏览器**打开上面的 Wiki 链接。

</div>

---

## ✨ 这是什么

MediaForge 把多个网盘统一接入，网盘里一有新影视落地，就**自动**完成：按 TMDB 规范重命名 → 生成 STRM/NFO → 联动 Emby 等媒体服务器刮削入库 → 通知你。

MediaForge 是**事件驱动**的：网盘里新增/改动了哪个文件，就只处理哪个，实时、增量、免打扰，不做定时全盘扫描。

## 🌟 核心亮点

- 🌐 **真正通用，不绑单一平台** —— 生成全播放器通用 STRM，走标准 WebDAV，**Emby / Jellyfin / Plex / Infuse / VLC 都能直接用**，不挑播放器。
- ⚡ **事件驱动、实时增量** —— 基于网盘原生变更日志，新增哪个只处理哪个，不做定时全盘扫描，快而省资源。
- 🎬 **STRM 一次生成、全平台通用** —— 内网走本地代理、外网自动 302 直链，换设备/换播放器/内外网切换都无需重新生成。
- 🔀 **两套 302 直链通路** —— Emby 302（挂载库播放）+ WebDAV 302（STRM 播放），各走各的通路。
- 🏷️ **先规范命名，再刮削** —— 落地即按 TMDB 规范重命名（电影/电视剧/季集识别、跨季集号映射），命名到位再入库，命中率高。
- 🎭 **豆瓣中文元数据 + 评分** —— 可生成带豆瓣评分和中文简介的 NFO，配合配套 Emby 插件在界面直接显示豆瓣评分。
- 👥 **同厂商多账号，独立不串号** —— 可同时接入同一平台的多个账号（如多个 115），各自独立生成 STRM，播放时凭稳定用户身份精准回到对应账号。
- ⚡ **跨网盘秒传** —— 网盘间转存用文件校验值直接在目标盘秒传，不下载不上传、几乎瞬间完成。已支持 115⇄阿里、百度→123/光鸭、天翼→123/光鸭、123→光鸭，后续持续增加。
- 💻 **全平台运行** —— Windows / macOS / Linux / 安卓 / 群晖等 NAS / Docker，一套逻辑到处跑。

## 📦 支持的网盘

115 · 阿里云盘 · 阿里云盘TV · 百度网盘 · 夸克 · 夸克TV · 123云盘 · 天翼云盘 · 移动云盘 · 光鸭云盘 · OpenList 聚合 · 标准 WebDAV

> 每家都用官方原生接口深度对接（浏览 / 上传 / 改名 / 删除 / 直链），不是简单挂个 WebDAV 套壳。

## 🚀 快速开始

MediaForge 通过 Docker 部署（支持 Linux / NAS / Docker）。

```bash
# 1. 准备目录 + .env（详见文档）
cp .env.example .env

# 2. 启动（推荐 Compose，挂载功能完整）
docker compose up -d
```

访问 `http://宿主机IP:7860` 打开 Web 管理界面，用邮箱注册/登录后即可添加网盘、开启自动流程。

> 📖 完整安装、镜像拉取、逐项配置见 [**安装部署**](https://github.com/lipin113/mediaforge/wiki/Installation) 与 [**快速上手**](https://github.com/lipin113/mediaforge/wiki/Quick-Start)。

## 📖 文档导航

| 入门 | 配置指南 | 关于 |
|---|---|---|
| [特性详解](https://github.com/lipin113/mediaforge/wiki/Features) | [登录与激活](https://github.com/lipin113/mediaforge/wiki/Login-and-Activation) · [添加网盘](https://github.com/lipin113/mediaforge/wiki/Add-Cloud-Drives) | [联系与支持](https://github.com/lipin113/mediaforge/wiki/Support) |
| [安装部署](https://github.com/lipin113/mediaforge/wiki/Installation) | [自动重命名](https://github.com/lipin113/mediaforge/wiki/Auto-Rename) · [STRM 库](https://github.com/lipin113/mediaforge/wiki/STRM-Library) | [开源致谢](https://github.com/lipin113/mediaforge/wiki/Credits) |
| [快速上手](https://github.com/lipin113/mediaforge/wiki/Quick-Start) | [NFO 与豆瓣](https://github.com/lipin113/mediaforge/wiki/NFO-and-Douban) · [Emby 配置](https://github.com/lipin113/mediaforge/wiki/Emby-Setup) | [声明](https://github.com/lipin113/mediaforge/wiki/Disclaimer) |
| [常见问题 FAQ](https://github.com/lipin113/mediaforge/wiki/FAQ) | [字幕](https://github.com/lipin113/mediaforge/wiki/Subtitles) · [云同步](https://github.com/lipin113/mediaforge/wiki/Cloud-Sync) · [TMDB 优选](https://github.com/lipin113/mediaforge/wiki/TMDB-Network) · [通知](https://github.com/lipin113/mediaforge/wiki/Notifications) | |

## 💬 联系与支持

- **QQ**：451436122 ｜ **Telegram 群**：https://t.me/+FcpCA-ngNcE4NWE1
- 更多联系方式、交流群与**捐赠支持**见 [联系与支持](https://github.com/lipin113/mediaforge/wiki/Support)

## 🙏 致谢与声明

- MediaForge 使用了众多优秀开源项目（MIT / BSD / Apache-2.0），详见 [开源致谢](https://github.com/lipin113/mediaforge/wiki/Credits)。
- MediaForge 仅为媒体整理工具，**不提供、不存储、不分发任何影视内容**；用户须对自己网盘中内容的来源与合法性负责。详见 [声明](https://github.com/lipin113/mediaforge/wiki/Disclaimer)。

<div align="center">
<br>
如果 MediaForge 对你有帮助，欢迎 ⭐ Star 支持项目持续开发。
</div>

