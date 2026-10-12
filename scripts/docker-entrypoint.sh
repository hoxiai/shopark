#!/usr/bin/env bash
set -e

# Explicit utility commands do not start or migrate the application.
case "$1" in
    doctor|--doctor|-d) set -- ./shoply "$@" ;;
esac

case "${1##*/}" in
    shoply|shoply-linux-*)
        doctor_requested=false
        doctor_subcommand=false
        doctor_config_value=false
        for doctor_arg in "${@:2}"; do
            if $doctor_config_value; then
                doctor_config_value=false
                continue
            fi
            case "$doctor_arg" in
                -c|--config) doctor_config_value=true ;;
                --doctor|-d) doctor_requested=true ;;
                --doctor=*|-d=*)
                    case "${doctor_arg#*=}" in
                        1|t|T|true|TRUE|True) doctor_requested=true ;;
                        0|f|F|false|FALSE|False) doctor_requested=false ;;
                    esac
                    ;;
                doctor) doctor_subcommand=true ;;
            esac
        done
        if $doctor_requested || $doctor_subcommand; then
            exec "$@"
        fi
        ;;
    *) exec "$@" ;;
esac

# 0. 初始化必要目录；plugins/app 通常是宿主机挂载，内置应用以镜像为准：
#    缺失时释放，版本与镜像不一致时整体替换（镜像升级或回滚都会跟随）。
mkdir -p public/uploads data config runtime plugins/app

builtin_apps_dir=/var/www/shoply/.builtin-plugins-app
app_version() {
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1/app.json" 2>/dev/null | head -n 1
}
if [ -d "$builtin_apps_dir" ]; then
    for builtin_app in "$builtin_apps_dir"/*/; do
        builtin_app="${builtin_app%/}"
        [ -d "$builtin_app" ] || continue
        app_name="${builtin_app##*/}"
        app_target="plugins/app/$app_name"
        image_version="$(app_version "$builtin_app")"
        if [ ! -d "$app_target" ]; then
            echo "[Shoply] Installing built-in application $app_name $image_version"
            cp -r "$builtin_app" "$app_target"
        elif [ "$(app_version "$app_target")" != "$image_version" ]; then
            if [ -e "$app_target/.git" ]; then
                echo "[Shoply] WARNING: $app_target is a source checkout; keeping it instead of image version $image_version" >&2
                continue
            fi
            echo "[Shoply] Replacing built-in application $app_name with image version $image_version"
            rm -rf "$app_target.next"
            cp -r "$builtin_app" "$app_target.next"
            rm -rf "$app_target"
            mv "$app_target.next" "$app_target"
        fi
    done
fi

# 等待 TCP 端口就绪工具函数
wait_for_port() {
    local host="$1"
    local port="$2"
    local name="$3"
    local max_retries=60
    local count=0

    echo "[Shoply] Waiting for $name at $host:$port to be ready..."
    while ! nc -z "$host" "$port" >/dev/null 2>&1 && ! (echo > "/dev/tcp/$host/$port") >/dev/null 2>&1; do
        sleep 1
        count=$((count + 1))
        if [ "$count" -ge "$max_retries" ]; then
            echo "[Shoply] ERROR: Timed out waiting for $name at $host:$port"
            exit 1
        fi
    done
    echo "[Shoply] $name is ready!"
}

# 1. 检查并等待外部数据库就绪
if [ -n "$SHOPLY_DB_HOST" ]; then
    DB_PORT="${SHOPLY_DB_PORT:-3306}"
    wait_for_port "$SHOPLY_DB_HOST" "$DB_PORT" "Database"
fi

# 2. 检查并等待外部 Redis 就绪
if [ -n "$SHOPLY_REDIS_ADDR" ]; then
    REDIS_HOST=$(echo "$SHOPLY_REDIS_ADDR" | cut -d: -f1)
    REDIS_PORT=$(echo "$SHOPLY_REDIS_ADDR" | cut -d: -f2)
    REDIS_PORT="${REDIS_PORT:-6379}"
    if [ -n "$REDIS_HOST" ]; then
        wait_for_port "$REDIS_HOST" "$REDIS_PORT" "Redis"
    fi
fi

# 3. 配置和应用注册先准备好，PHP CLI 才能读取同一份配置与注册表。
if ! command -v shoply-prepare >/dev/null 2>&1; then
    echo "[Shoply] ERROR: shoply-prepare is missing from the release image" >&2
    exit 1
fi
shoply-prepare --config ./config/conf.yaml

# 4. 迁移失败不启动 HTTP；每次发布都检查应用模型，而非依赖临时根目录标记。
if [ ! -f "plugins/shoply" ] || ! command -v php >/dev/null 2>&1; then
    echo "[Shoply] ERROR: PHP CLI or plugins/shoply is missing" >&2
    exit 1
fi
echo "[Shoply] Syncing PHP plugin database tables..."
(cd plugins && php shoply db:sync)

echo "[Shoply] Starting application server..."
exec "$@"
