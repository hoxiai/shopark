# Shoply Official Distribution

> **Shoply** is a next-generation, high-performance multilingual e-commerce platform built for global direct-to-consumer (DTC) brands and B2B commerce. Powered by a lightning-fast Go transaction & AI engine, responsive SSR storefront, modern Naive UI administration dashboard, and an extensible PHP application ecosystem.

This repository is the **official release distribution** for Shoply, providing turnkey Docker and Podman orchestration, production-ready environment templates, and automated operations scripts.

- **Global Repository**: [https://github.com/hoxiai/shoply](https://github.com/hoxiai/shoply)
- **China Mirror**: [https://gitcode.com/hoxiai/shoply](https://gitcode.com/hoxiai/shoply)

---

## 🚀 Quick Start (Under 1 Minute)

### Prerequisites
- **Docker** 20.10+ and **Docker Compose** v2+ (or **Podman** 4.0+)
- Linux / macOS / Windows (WSL2)
- Recommended: 2 vCPUs / 4GB RAM or higher

### 1. Clone the Repository
```bash
git clone https://github.com/hoxiai/shoply.git
cd shoply
```

### 2. Launch Services (Smart Port Detection & Setup)
Run the root helper script directly:
```bash
./shoply.sh start
```
> **💡 Smart Detection Features**:
> - Scans host ports **3306 (MySQL)** and **6379 (Redis)** automatically.
> - **Existing host MySQL / Redis detected**: Prompts to connect directly without starting unnecessary containers.
> - **No existing services found**: Automatically spins up containerized MySQL 8.0 & Redis 7 with auto-generated secure credentials.
> - For international deployments, switch `SHOPLY_IMAGE_REGISTRY=ghcr.io` in `.env` if desired.

### 3. Access Shoply
- **Storefront**: `http://localhost:5490`
- **Admin Dashboard**: `http://localhost:5490/admin/`
- **Default Account**: `admin@shoply.page` (password entered during setup)

---

## 🛠️ Management CLI (`shoply.sh`)

Manage your instance easily via `./scripts/shoply.sh`:

```bash
# Start all containers in detached mode
./scripts/shoply.sh start

# Stop running containers
./scripts/shoply.sh stop

# Restart services
./scripts/shoply.sh restart

# Check container health and status
./scripts/shoply.sh status

# Follow real-time application logs
./scripts/shoply.sh logs

# Check and perform smooth online update (supports version pinning & auto-rollback)
./scripts/shoply.sh update
# Or run the dedicated upgrade script:
bash scripts/upgrade.sh              # Update to the latest release
bash scripts/upgrade.sh v1.0.1       # Upgrade to a specific version
bash scripts/upgrade.sh --check      # Check for available updates
bash scripts/upgrade.sh --rollback   # Rollback to the previous stable backup

# Build local container image (see below)
./scripts/shoply.sh build v1.0.0
```

---

## 🔨 Building Image Locally (Optional)

Using official prebuilt images via `./scripts/shoply.sh start` is recommended. To build custom images:

```bash
# Using build shortcut (supports Docker / Podman)
./build.sh v1.0.0

# Or via management CLI
./scripts/shoply.sh build v1.0.0
```
> **Note**: Building images requires closed-source binaries and runtime assets. If local assets are missing, the build script automatically fetches and extracts the corresponding release package (`shoply-*.tar.gz`) from official Releases (GitHub or GitCode, configurable via `--github` / `--gitcode`). Offline manual placement of the archive is also supported.

---

## 🛡️ Podman (Rootless Support)

Shoply is engineered to run seamlessly with Rootless Podman without root privileges:
1. Runs on standard unprivileged port `5490` (no `<1024` privilege needed).
2. Volume mounts in `docker-compose.yml` include `:Z` flags for automatic SELinux label configuration.

Start via:
```bash
podman-compose up -d
# or using the helper script:
./scripts/shoply.sh start
```

---

## 🌐 Production Reverse Proxy (Nginx)

For production environments, reverse proxy via Nginx or Caddy with HTTPS:

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

        # WebSocket support for AI Chat & real-time events
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

---

## 💾 Data Persistence & Backup

Persistent application state is isolated in:
- `./data`: runtime store and package releases
- `./public/uploads`: uploaded media and catalogs
- `mysql_data`: database volume (or backup via `mysqldump`)
- `redis_data`: cache & session data volume

---

## 📄 License & Commercial Support

- This distribution is provided under the Shoply Commercial / End User License.
- For product updates, custom apps, and enterprise support, visit [Hoxi AI](https://hoxi.ai).
