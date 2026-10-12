#!/usr/bin/env bash
set -e

# ========================================================
# Shoply 生产镜像构建脚本 (支持 Docker / Podman)
# ========================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

# 1. 检测容器引擎
detect_engine() {
    if [ -n "$CONTAINER_ENGINE" ]; then
        echo "$CONTAINER_ENGINE"
    elif command -v podman >/dev/null 2>&1; then
        echo "podman"
    elif command -v docker >/dev/null 2>&1; then
        echo "docker"
    else
        echo ""
    fi
}

ENGINE=$(detect_engine)
if [ -z "$ENGINE" ]; then
    echo "[Shoply] 错误: 未检测到 podman 或 docker，请先安装其中之一。" >&2
    exit 1
fi

# 2. 参数解析与默认值
VERSION="${VERSION:-${1:-latest}}"
IMAGE_NAME="${IMAGE_NAME:-hoxiai/shoply}"
BASE_IMAGE="${SHOPLY_BASE_IMAGE:-registry.cn-hangzhou.aliyuncs.com/hoxiai/shoply-base:latest}"
PLATFORM="${SHOPLY_PLATFORM:-linux/amd64}"
REGISTRY="${SHOPLY_REGISTRY:-registry.cn-hangzhou.aliyuncs.com}"
DO_PUSH=false

for arg in "$@"; do
    case "$arg" in
        --push) DO_PUSH=true ;;
    esac
done

echo "=========================================="
echo "  Shoply 容器镜像构建"
echo "  容器引擎: $ENGINE"
echo "  镜像版本: $VERSION"
echo "  目标平台: $PLATFORM"
echo "  基础镜像: $BASE_IMAGE"
echo "=========================================="

# 3. 检查构建依赖（二进制文件与运行时资产）
check_assets() {
    local missing=0

    # 优先检查本地是否已有可执行二进制与静态资产
    if [ ! -f "shoply" ] && [ ! -f "dist/shoply-linux-amd64" ] && [ ! -f "../dist/shoply-linux-amd64" ]; then
        missing=1
    fi
    if [ ! -d "plugins" ] || [ ! -d "public" ] || [ ! -d "template" ] || [ ! -d "resource" ]; then
        missing=1
    fi

    if [ "$missing" -eq 1 ]; then
        echo "[Shoply] 提示: 当前目录缺少完整的运行资产包 (shoply, plugins, public, template, resource)。"
        
        # 尝试查找本地是否存在打包好的 release tarball
        local TARBALL=$(ls shoply-*.tar.gz 2>/dev/null | head -n 1 || true)
        if [ -n "$TARBALL" ] && [ -f "$TARBALL" ]; then
            echo "[Shoply] 检测到本地发行包 $TARBALL，正在自动解压..."
            tar -xzf "$TARBALL"
        else
            echo ""
            echo "======================================================================"
            echo "说明: 本仓库为配置与编排仓库，构建镜像需要运行二进制与资源资产。"
            echo "您可以任选以下方式之一:"
            echo "  1. 直接使用官方预构建好的镜像运行 (推荐，无需本地构建):"
            echo "     ./scripts/shoply.sh start"
            echo "  2. 从 GitHub/GitCode Releases 下载对应版本的 shoply-*.tar.gz 放入本目录解压后再执行构建"
            echo "======================================================================"
            exit 1
        fi
    fi
}

check_assets

# 确定二进制路径
SHOPLY_BIN="shoply"
SHOPLY_PREPARE_BIN="shoply-prepare"

if [ ! -f "$SHOPLY_BIN" ] && [ -f "dist/shoply-linux-amd64" ]; then
    SHOPLY_BIN="dist/shoply-linux-amd64"
    SHOPLY_PREPARE_BIN="dist/shoply-prepare-linux-amd64"
elif [ ! -f "$SHOPLY_BIN" ] && [ -f "../dist/shoply-linux-amd64" ]; then
    SHOPLY_BIN="../dist/shoply-linux-amd64"
    SHOPLY_PREPARE_BIN="../dist/shoply-prepare-linux-amd64"
fi

# 4. 执行构建
echo "[Shoply] 开始构建镜像..."
$ENGINE build \
    --platform "$PLATFORM" \
    --build-arg SHOPLY_BASE_IMAGE="$BASE_IMAGE" \
    --build-arg SHOPLY_PLATFORM="$PLATFORM" \
    --build-arg SHOPLY_BINARY="$SHOPLY_BIN" \
    --build-arg SHOPLY_PREPARE_BINARY="$SHOPLY_PREPARE_BIN" \
    -t "${IMAGE_NAME}:${VERSION}" \
    -t "${IMAGE_NAME}:latest" \
    -t "${REGISTRY}/${IMAGE_NAME}:${VERSION}" \
    -t "${REGISTRY}/${IMAGE_NAME}:latest" \
    .

echo "[Shoply] 镜像构建成功: ${IMAGE_NAME}:${VERSION}"

# 5. 推送（可选）
if [ "$DO_PUSH" = true ]; then
    echo "[Shoply] 正在推送镜像至 ${REGISTRY}..."
    $ENGINE push "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    $ENGINE push "${REGISTRY}/${IMAGE_NAME}:latest"
    echo "[Shoply] 镜像推送完成！"
fi
