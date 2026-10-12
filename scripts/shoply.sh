#!/usr/bin/env bash
set -e

# ========================================================
# Shoply 运维管理便捷脚本 (支持 Docker / Podman)
# ========================================================

# 定位脚本所在工作目录（发布包根目录）
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# 1. 自动检测容器编排命令
detect_compose() {
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    elif command -v podman-compose >/dev/null 2>&1; then
        echo "podman-compose"
    elif command -v podman >/dev/null 2>&1 && podman compose version >/dev/null 2>&1; then
        echo "podman compose"
    elif command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo ""
    fi
}

COMPOSE_CMD=$(detect_compose)
if [ -z "$COMPOSE_CMD" ]; then
    echo "[Shoply] 错误: 未检测到 docker compose 或 podman compose，请先安装 Docker 或 Podman 环境。" >&2
    exit 1
fi

# 2. 检查 .env 配置文件
check_env() {
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            echo "[Shoply] 未检测到 .env 配置文件，正在根据 .env.example 自动生成..."
            cp .env.example .env
            echo "[Shoply] 已创建 .env，建议先根据需要调整配置（例如管理员密码和密钥），然后再启动。"
        else
            echo "[Shoply] 错误: 未找到 .env 或 .env.example 配置文件。" >&2
            exit 1
        fi
    fi
}

# 3. 命令路由
case "$1" in
    start|up)
        check_env
        echo "[Shoply] 正在启动服务 (使用: $COMPOSE_CMD)..."
        $COMPOSE_CMD up -d
        echo "[Shoply] 服务启动成功！访问入口端口见 .env 配置 (默认: http://localhost:5490)"
        ;;
    stop|down)
        echo "[Shoply] 正在停止服务..."
        $COMPOSE_CMD down
        echo "[Shoply] 服务已停止。"
        ;;
    restart)
        check_env
        echo "[Shoply] 正在重启服务..."
        $COMPOSE_CMD restart
        echo "[Shoply] 服务已重启。"
        ;;
    status|ps)
        $COMPOSE_CMD ps
        ;;
    logs)
        shift
        $COMPOSE_CMD logs -f "${@:-shoply}"
        ;;
    update|pull)
        check_env
        echo "[Shoply] 正在拉取最新容器镜像..."
        $COMPOSE_CMD pull shoply
        echo "[Shoply] 正在平滑更新容器..."
        $COMPOSE_CMD up -d shoply
        echo "[Shoply] 更新完成！"
        ;;
    help|*)
        echo "Shoply 容器管理工具"
        echo ""
        echo "用法: ./scripts/shoply.sh [命令]"
        echo ""
        echo "常用命令:"
        echo "  start     启动所有服务（后台运行）"
        echo "  stop      停止并移除当前容器"
        echo "  restart   重启所有服务"
        echo "  status    查看各服务运行状态"
        echo "  logs      跟踪实时日志 (例: ./scripts/shoply.sh logs)"
        echo "  update    拉取最新镜像并平滑更新应用容器"
        echo "  help      显示此帮助信息"
        echo ""
        ;;
esac
