#!/usr/bin/env bash
set -e

# ========================================================
# Shoply 智能运维与运行管理工具 (支持 Docker / Podman)
# ========================================================

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

# 2. 端口检测辅助函数
check_port() {
    local host="$1"
    local port="$2"
    if command -v nc >/dev/null 2>&1; then
        nc -z -w 2 "$host" "$port" >/dev/null 2>&1
    else
        (echo > "/dev/tcp/$host/$port") >/dev/null 2>&1
    fi
}

# 3. 随机字符串生成工具
generate_secret() {
    local length="${1:-32}"
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex "$((length / 2))"
    else
        LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c "$length" || echo "shoply_rand_key_$(date +%s)"
    fi
}

# 4. 智能环境向导配置
interactive_setup() {
    echo "========================================================"
    echo "       Shoply 部署配置智能向导"
    echo "========================================================"
    echo ""

    local use_embedded_mysql="true"
    local db_host="mysql"
    local db_port="3306"
    local db_name="shoply"
    local db_user="shoply"
    local db_pass=""
    local mysql_root_pass=""

    local use_embedded_redis="true"
    local redis_addr="redis:6379"
    local redis_pass=""

    local is_interactive=false
    if [ -t 0 ]; then
        is_interactive=true
    fi

    # ------------------ MySQL 检测 ------------------
    if check_port 127.0.0.1 3306; then
        echo "[Shoply] 🔍 检测到宿主机 3306 端口已有运行中的 MySQL 服务。"
        local choice_mysql="Y"
        if [ "$is_interactive" = true ]; then
            read -r -p "是否直接使用宿主机现有的 MySQL 数据库？ [Y/n]: " input_choice_mysql
            choice_mysql=${input_choice_mysql:-Y}
        fi

        if [[ "$choice_mysql" =~ ^[Yy]$ ]]; then
            use_embedded_mysql="false"
            db_host="host.docker.internal"
            if [ "$is_interactive" = true ]; then
                read -r -p "请输入 MySQL 数据库名称 [默认: shoply]: " input_db
                db_name=${input_db:-shoply}
                read -r -p "请输入 MySQL 用户名 [默认: root]: " input_user
                db_user=${input_user:-root}
                read -r -p "请输入 MySQL 密码 [留空表示无密码]: " input_pass
                db_pass=$input_pass
            else
                db_pass="root"
            fi

            # 尝试通过 mysql 客户端自动建库
            if command -v mysql >/dev/null 2>&1 && [ -n "$db_pass" ]; then
                mysql -h 127.0.0.1 -P 3306 -u "$db_user" -p"$db_pass" -e "CREATE DATABASE IF NOT EXISTS \`${db_name}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >/dev/null 2>&1 || true
            fi
            echo "[Shoply] ✔️ 将连接宿主机 MySQL (${db_host}:${db_port}/${db_name})，跳过启动 MySQL 容器。"
        else
            echo "[Shoply] ✔️ 将在容器中独立启动 MySQL 8.0。"
            if [ "$is_interactive" = true ]; then
                read -r -p "请设置容器 MySQL 数据库密码 [留空自动生成随机强密码]: " input_db_pass
                if [ -n "$input_db_pass" ]; then
                    db_pass="$input_db_pass"
                    mysql_root_pass="$input_db_pass"
                else
                    db_pass=$(generate_secret 16)
                    mysql_root_pass=$(generate_secret 20)
                fi
            else
                db_pass=$(generate_secret 16)
                mysql_root_pass=$(generate_secret 20)
            fi
        fi
    else
        echo "[Shoply] ℹ️ 未检测到宿主机 MySQL 3306 端口，将在容器中自动启动 MySQL 8.0。"
        if [ "$is_interactive" = true ]; then
            read -r -p "请设置容器 MySQL 数据库密码 [留空自动生成随机强密码]: " input_db_pass
            if [ -n "$input_db_pass" ]; then
                db_pass="$input_db_pass"
                mysql_root_pass="$input_db_pass"
            else
                db_pass=$(generate_secret 16)
                mysql_root_pass=$(generate_secret 20)
            fi
        else
            db_pass=$(generate_secret 16)
            mysql_root_pass=$(generate_secret 20)
        fi
    fi
    echo ""

    # ------------------ Redis 检测 ------------------
    if check_port 127.0.0.1 6379; then
        echo "[Shoply] 🔍 检测到宿主机 6379 端口已有运行中的 Redis 服务。"
        local choice_redis="Y"
        if [ "$is_interactive" = true ]; then
            read -r -p "是否直接使用宿主机现有的 Redis 缓存？ [Y/n]: " input_choice_redis
            choice_redis=${input_choice_redis:-Y}
        fi

        if [[ "$choice_redis" =~ ^[Yy]$ ]]; then
            use_embedded_redis="false"
            redis_addr="host.docker.internal:6379"
            if [ "$is_interactive" = true ]; then
                read -r -p "请输入宿主机 Redis 访问密码 [若无密码直接回车]: " input_redis_pass
                redis_pass=$input_redis_pass
            fi
            echo "[Shoply] ✔️ 将连接宿主机 Redis (${redis_addr})，跳过启动 Redis 容器。"
        else
            echo "[Shoply] ✔️ 将在容器中独立启动 Redis 7。"
            if [ "$is_interactive" = true ]; then
                read -r -p "请设置容器 Redis 密码 [留空自动生成随机密码]: " input_redis_pass
                if [ -n "$input_redis_pass" ]; then
                    redis_pass="$input_redis_pass"
                else
                    redis_pass=$(generate_secret 16)
                fi
            else
                redis_pass=$(generate_secret 16)
            fi
        fi
    else
        echo "[Shoply] ℹ️ 未检测到宿主机 Redis 6379 端口，将在容器中自动启动 Redis 7。"
        if [ "$is_interactive" = true ]; then
            read -r -p "请设置容器 Redis 密码 [留空自动生成随机密码]: " input_redis_pass
            if [ -n "$input_redis_pass" ]; then
                redis_pass="$input_redis_pass"
            else
                redis_pass=$(generate_secret 16)
            fi
        else
            redis_pass=$(generate_secret 16)
        fi
    fi
    echo ""

    # ------------------ 管理员账户与密钥 ------------------
    local admin_pwd="AdminPassword123!"
    if [ "$is_interactive" = true ]; then
        while true; do
            read -r -p "请输入超级管理员登录密码 (登录邮箱: admin@shoply.page) [至少8位]: " input_admin_pwd
            if [ -z "$input_admin_pwd" ]; then
                echo "[Shoply] 提示: 密码不能为空，请输入管理员密码。"
            elif [ ${#input_admin_pwd} -lt 8 ]; then
                echo "[Shoply] 提示: 密码长度至少需要8位，请重新输入。"
            else
                admin_pwd="$input_admin_pwd"
                break
            fi
        done
    fi

    local jwt_sign_key=$(generate_secret 24)
    local jwt_secret_key=$(generate_secret 32)

    # ------------------ 写入 .env 文件 ------------------
    cat <<EOF > .env
# ========================================================
# Shoply 运行环境配置文件 (.env) - 智能向导自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ========================================================

# 容器镜像配置
SHOPLY_IMAGE_REGISTRY=registry.cn-hangzhou.aliyuncs.com
SHOPLY_IMAGE_NAME=hoxiai/shoply
SHOPLY_VERSION=latest
SHOPLY_HTTP_PORT=5490

# 架构与服务开关 (控制是否启动内置容器)
USE_EMBEDDED_MYSQL=${use_embedded_mysql}
USE_EMBEDDED_REDIS=${use_embedded_redis}

# 数据库配置
SHOPLY_DB_DRIVER=mysql
SHOPLY_DB_HOST=${db_host}
SHOPLY_DB_PORT=${db_port}
SHOPLY_DB_DATABASE=${db_name}
SHOPLY_DB_USERNAME=${db_user}
SHOPLY_DB_PASSWORD=${db_pass}
SHOPLY_MYSQL_ROOT_PASSWORD=${mysql_root_pass}

# 缓存配置
SHOPLY_REDIS_ADDR=${redis_addr}
SHOPLY_REDIS_PASSWORD=${redis_pass}
SHOPLY_REDIS_DB=0

# 站点与超级管理员
SHOPLY_STORE_NAME=Shoply Store
SHOPLY_SITE_URL=http://localhost:5490
SHOPLY_SITE_EMAIL=admin@shoply.page
SHOPLY_SITE_PASSWORD=${admin_pwd}

# 安全密钥
SHOPLY_JWT_SIGN_KEY=${jwt_sign_key}
SHOPLY_JWT_SECRET_KEY=${jwt_secret_key}
SHOPLY_JWT_ADMIN_PERMISSION_MODE=enforce
EOF

    echo "========================================================"
    echo "  配置生成成功: .env"
    echo "  - 数据库: ${db_host}:${db_port} (${db_name})"
    echo "  - 缓  存: ${redis_addr}"
    echo "  - 管理员: admin@shoply.page (初始密码: ${admin_pwd})"
    echo "========================================================"
    echo ""
}

# 5. 计算并获取 Profile 参数
get_profile_args() {
    local args=()
    if [ -f ".env" ]; then
        local use_mysql=$(grep -E "^USE_EMBEDDED_MYSQL=" .env 2>/dev/null | cut -d= -f2 | tr -d ' "\r' || true)
        local use_redis=$(grep -E "^USE_EMBEDDED_REDIS=" .env 2>/dev/null | cut -d= -f2 | tr -d ' "\r' || true)

        if [ "$use_mysql" = "true" ] || [ -z "$use_mysql" ]; then
            args+=(--profile mysql)
        fi
        if [ "$use_redis" = "true" ] || [ -z "$use_redis" ]; then
            args+=(--profile redis)
        fi
    else
        args+=(--profile mysql --profile redis)
    fi
    echo "${args[@]}"
}

# 6. 命令路由
case "$1" in
    init|config)
        interactive_setup
        ;;
    start|up)
        if [ ! -f ".env" ]; then
            interactive_setup
        fi
        PROFILE_ARGS=$(get_profile_args)
        echo "[Shoply] 正在启动服务 (使用: $COMPOSE_CMD $PROFILE_ARGS)..."
        $COMPOSE_CMD $PROFILE_ARGS up -d
        echo ""
        echo "[Shoply] 🚀 服务启动成功！"
        echo "[Shoply] 前台入口: http://localhost:5490"
        echo "[Shoply] 管理后台: http://localhost:5490/admin/"
        echo "[Shoply] 登录账号: admin@shoply.page"
        ;;
    stop|down)
        PROFILE_ARGS=$(get_profile_args)
        echo "[Shoply] 正在停止服务..."
        $COMPOSE_CMD $PROFILE_ARGS down
        echo "[Shoply] 服务已停止。"
        ;;
    restart)
        PROFILE_ARGS=$(get_profile_args)
        echo "[Shoply] 正在重启服务..."
        $COMPOSE_CMD $PROFILE_ARGS restart
        echo "[Shoply] 服务已重启。"
        ;;
    status|ps)
        PROFILE_ARGS=$(get_profile_args)
        $COMPOSE_CMD $PROFILE_ARGS ps
        ;;
    logs)
        PROFILE_ARGS=$(get_profile_args)
        shift
        $COMPOSE_CMD $PROFILE_ARGS logs -f "${@:-shoply}"
        ;;
    update|pull)
        PROFILE_ARGS=$(get_profile_args)
        echo "[Shoply] 正在拉取最新容器镜像..."
        $COMPOSE_CMD $PROFILE_ARGS pull shoply
        echo "[Shoply] 正在平滑更新容器..."
        $COMPOSE_CMD $PROFILE_ARGS up -d shoply
        echo "[Shoply] 更新完成！"
        ;;
    build)
        shift
        exec ./scripts/build-image.sh "$@"
        ;;
    help|*)
        echo "Shoply 容器管理工具"
        echo ""
        echo "用法: ./scripts/shoply.sh [命令]"
        echo ""
        echo "常用命令:"
        echo "  start     启动服务（若未初始化会自动启动智能检测与向导）"
        echo "  init      重新运行配置向导生成 .env 配置"
        echo "  stop      停止并移除当前容器"
        echo "  restart   重启所有服务"
        echo "  status    查看各服务运行状态"
        echo "  logs      跟踪实时日志 (例: ./scripts/shoply.sh logs)"
        echo "  update    拉取最新镜像并平滑更新应用容器"
        echo "  build     构建本地 Docker / Podman 镜像 (例: ./scripts/shoply.sh build v1.0.0)"
        echo "  help      显示此帮助信息"
        echo ""
        ;;
esac
