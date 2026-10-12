# Shoply 官方部署分发库

> **Shoply** 是专为跨境与品牌出海打造的下一代高性能多语言独立站电商系统。底层由 Go 高性能交易与 AI 引擎驱动，前端采用响应式 SSR 动态渲染与 Naive UI 后台，并深度融合 PHP 插件与开放应用市场。

本仓库是 **Shoply 官方发布版**，提供直接运行的容器编排模版、一键部署脚本及镜像配置。无需从零编译，几分钟即可在服务器上完成私有化部署。

- **国内仓库**：[https://gitcode.com/hoxiai/shoply](https://gitcode.com/hoxiai/shoply) （默认配置国内镜像源，开箱即用）
- **国际仓库**：[https://github.com/hoxiai/shoply](https://github.com/hoxiai/shoply)

---

## 🚀 1 分钟快速启动

### 准备环境
- **Docker** 20.10+ 及 **Docker Compose** v2+ （或 **Podman** 4.0+）
- Linux / macOS / Windows (WSL2)
- 建议配置：2 核 CPU / 4GB 内存以上

### 1. 克隆本仓库并进入目录
```bash
git clone https://gitcode.com/hoxiai/shoply.git
cd shoply
```

### 2. 一键启动（智能向导与端口自动检测）
进入目录后，直接执行根目录管理脚本：
```bash
./shoply.sh start
```
> **💡 智能检测特性**：
> - 脚本会自动扫描宿主机 **3306 (MySQL)** 与 **6379 (Redis)** 端口。
> - **若宿主机已有 MySQL/Redis**：会提示确认并引导输入数据库库名、账号密码，Shoply 将直接连接已有服务，**不启动多余容器**。
> - **若未检测到或选择独立运行**：会自动以容器方式一键拉起 MySQL 8.0 与 Redis 7，并自动生成高强度随机密码写入 `.env`。
> - 默认配置已指向**阿里云国内公开镜像源**，国内服务器拉取极速稳定。

### 3. 访问系统
- **商城前台**：`http://localhost:5490`
- **管理后台**：`http://localhost:5490/admin/`
- **默认管理员**：`admin@shoply.page`（密码为您在启动向导中输入的管理员密码）

---

## 🛠️ 运维与管理命令

通过便捷管理脚本 `./scripts/shoply.sh`：

```bash
# 启动所有服务 (后台守护进程)
./scripts/shoply.sh start

# 停止并移除容器
./scripts/shoply.sh stop

# 重启所有服务
./scripts/shoply.sh restart

# 查看服务运行状态
./scripts/shoply.sh status

# 跟踪查看主服务实时日志
./scripts/shoply.sh logs

# 一键检查并在线平滑更新升级 (支持指定版本与自动回滚)
./scripts/shoply.sh update
# 或直接运行专用升级脚本:
bash scripts/upgrade.sh              # 检查并更新至最新版本
bash scripts/upgrade.sh v1.0.1       # 升级至指定版本
bash scripts/upgrade.sh --check      # 仅检查是否有新版本
bash scripts/upgrade.sh --rollback   # 故障时快速回滚至上一稳定版本

# 本地构建镜像 (详见下方说明)
./scripts/shoply.sh build v1.0.0
```

---

## 🔨 本地构建镜像 (可选)

官方推荐直接拉取预构建镜像运行（开箱即用）。若您需要本地定制或基于离线包构建：

```bash
# 执行构建脚本 (支持 Docker / Podman 自动适配)
./build.sh v1.0.0

# 或通过运维脚本执行:
./scripts/shoply.sh build v1.0.0
```
> **说明**：构建镜像需要闭源二进制与运行资产。执行构建时若本地缺少资产，脚本会自动从官方 Release（国内优先 GitCode，海外优先 GitHub，支持 `--gitcode` 或 `--github` 指定）拉取对应版本的 `shoply-*.tar.gz` 离线资产包并解压构建；亦支持在离线环境下提前放置安装包后直接构建。

---

## 🛡️ Podman (Rootless 免 Root 部署)

Shoply 完全遵循安全最佳实践，完美兼容 Podman 原生 Rootless 模式：
1. 默认运行端口为 `5490`，无需绑定特权端口（<1024）。
2. `docker-compose.yml` 中的挂载目录已配置 `:Z` 标签，原生兼容 SELinux 策略。

启动命令：
```bash
podman-compose up -d
# 或通过脚本自动探测运行:
./scripts/shoply.sh start
```

---

## 🌐 生产反向代理 (Nginx 示例)

在生产环境中，推荐通过 Nginx 或 Caddy 处理 HTTPS 证书与域名反代：

```nginx
server {
    listen 80;
    server_name mall.yourdomain.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name mall.yourdomain.com;

    ssl_certificate     /path/to/fullchain.pem;
    ssl_certificate_key /path/to/privkey.pem;

    client_max_body_size 50m;

    location / {
        proxy_pass http://127.0.0.1:5490;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket 支持 (AI 对话与实时通信)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## 💾 数据持久化与目录说明

所有需要持久化和支持外部二开的目录均位于当前目录下，备份、迁移或二次开发只需要关注这些目录：
- `./config`：系统主配置 (`conf.yaml`，包含数据库和站点配置)
- `./data`：本地数据存储、缓存与上传的插件包
- `./data/theme-releases`：商家后台上传安装的独立主题版本
- `./plugins/app`：**业务插件与应用目录**（容器首次启动会自动释放全套官方内置插件，支持在宿主机直接修改或二次开发）
- `./public/uploads`：**商品图片与用户上传资源**（商品主图、品牌 Logo、附件等永久持久化）
- `./runtime`：系统运行日志 (`runtime/logs`)，便于宿主机随时排查故障
- `mysql_data` / `redis_data`：内置数据库与缓存数据卷

---

## 📄 开源与商业授权

- 本仓库的分发文件遵循商业/闭源最终用户许可，详情请参见具体授权协议。
- 更多产品动态与生态支持，请关注 [Hoxi AI 官网](https://hoxi.ai)。
