#!/usr/bin/env bash
set -e

# ========================================================
# Shoply 生产镜像构建脚本 (支持 Docker / Podman)
# 自动适配国内 GitCode 与海外 GitHub Releases 闭源资产包
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
VERSION=""
IMAGE_NAME="${IMAGE_NAME:-hoxiai/shoply}"
if [ -z "$SHOPLY_BASE_IMAGE" ]; then
    if $ENGINE image exists shoply:latest 2>/dev/null; then
        BASE_IMAGE="shoply:latest"
    else
        BASE_IMAGE="registry.cn-hangzhou.aliyuncs.com/hoxiai/shoply:latest"
    fi
else
    BASE_IMAGE="$SHOPLY_BASE_IMAGE"
fi
PLATFORM="${SHOPLY_PLATFORM:-linux/amd64}"
REGISTRY="${SHOPLY_REGISTRY:-registry.cn-hangzhou.aliyuncs.com}"
DO_PUSH=false
SHOPLY_MIRROR="${SHOPLY_MIRROR:-}"

for arg in "$@"; do
    case "$arg" in
        --push) DO_PUSH=true ;;
        --mirror=*) SHOPLY_MIRROR="${arg#*=}" ;;
        --gitcode|--cn) SHOPLY_MIRROR="gitcode" ;;
        --github|--intl|--global) SHOPLY_MIRROR="github" ;;
        -*) ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$arg"
            fi
            ;;
    esac
done

VERSION="${VERSION:-${SHOPLY_VERSION:-latest}}"

echo "=========================================="
echo "  Shoply 容器镜像构建"
echo "  容器引擎: $ENGINE"
echo "  镜像版本: $VERSION"
echo "  目标平台: $PLATFORM"
echo "  基础镜像: $BASE_IMAGE"
if [ -n "$SHOPLY_MIRROR" ]; then
    echo "  指定源:   $SHOPLY_MIRROR"
fi
echo "=========================================="

# 3. 自动探测网络镜像源优先级 (国内优先 GitCode，海外优先 GitHub)
detect_mirror_priority() {
    if [ -n "$SHOPLY_MIRROR" ]; then
        case "$SHOPLY_MIRROR" in
            gitcode|cn|gitee)
                echo "gitcode github"
                return
                ;;
            github|global|intl)
                echo "github gitcode"
                return
                ;;
        esac
    fi

    local is_cn=0
    local tz=$(date +%z 2>/dev/null || echo "")
    if [[ "$tz" == "+0800" ]] || [[ "${LANG:-}" == *zh_* ]] || [[ "${LC_ALL:-}" == *zh_* ]]; then
        is_cn=1
    fi

    if [ "$is_cn" -eq 1 ]; then
        echo "gitcode github"
    else
        echo "github gitcode"
    fi
}

# 下载工具封装 (优先使用 curl，备选 wget)
download_file() {
    local url="$1"
    local dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -f -L --connect-timeout 10 --retry 1 --progress-bar -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$dest" "$url"
    else
        echo "[Shoply] 错误: 未检测到 curl 或 wget，无法自动下载资产包。" >&2
        return 1
    fi
}

# 尝试从指定镜像平台 API 解析 latest 版本 tag
resolve_latest_tag() {
    local source="$1"
    local api_url=""
    if [ "$source" = "gitcode" ]; then
        api_url="https://api.gitcode.com/api/v5/repos/hoxiai/shoply/releases/latest"
    elif [ "$source" = "github" ]; then
        api_url="https://api.github.com/repos/hoxiai/shoply/releases/latest"
    fi

    local resp=""
    if command -v curl >/dev/null 2>&1; then
        resp=$(curl -s -m 5 "$api_url" 2>/dev/null || true)
    elif command -v wget >/dev/null 2>&1; then
        resp=$(wget -q -T 5 -O - "$api_url" 2>/dev/null || true)
    fi

    echo "$resp" | grep -o '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' | head -n 1 | sed -E 's/.*"([^"]+)"$/\1/'
}

# 从指定源尝试下载 Release 资产
try_download_from_source() {
    local source="$1"
    local tag="$2"
    local filename="$3"
    local url=""

    if [ "$source" = "gitcode" ]; then
        url="https://gitcode.com/hoxiai/shoply/releases/download/${tag}/${filename}"
    elif [ "$source" = "github" ]; then
        url="https://github.com/hoxiai/shoply/releases/download/${tag}/${filename}"
    else
        return 1
    fi

    local source_name="国内 GitCode"
    if [ "$source" = "github" ]; then
        source_name="海外 GitHub"
    fi

    echo "[Shoply] 尝试从 ${source_name} 下载资产包: ${filename} ..."
    echo "[Shoply] URL: $url"

    local tmp_file="${filename}.tmp.$$"
    if download_file "$url" "$tmp_file"; then
        mv "$tmp_file" "$filename"
        echo "[Shoply] ${source_name} 资产包下载成功！"
        return 0
    else
        rm -f "$tmp_file"
        echo "[Shoply] 从 ${source_name} 下载未命中或网络失败。"
        return 1
    fi
}

# 4. 检查构建依赖（二进制文件与运行时资产）
check_assets() {
    # 步骤 4.1：检查是否已有解压好的可执行文件与核心资产目录
    local has_bin=0
    local has_dirs=0

    if [ -f "shoply" ] || [ -f "shoply-linux-amd64" ] || [ -f "dist/shoply-linux-amd64" ] || [ -f "../dist/shoply-linux-amd64" ]; then
        has_bin=1
    fi
    if [ -d "plugins" ] && [ -d "public" ] && [ -d "template" ] && [ -d "resource" ]; then
        has_dirs=1
    fi

    if [ "$has_bin" -eq 1 ] && [ "$has_dirs" -eq 1 ]; then
        echo "[Shoply] 检测到本地运行资产齐全 (二进制与静态目录已就绪)。"
        return 0
    fi

    echo "[Shoply] 提示: 当前目录缺少完整的运行资产包 (shoply, plugins, public, template, resource)。"

    # 步骤 4.2：检查本地是否存在已有的 tarball
    local TARBALL=""
    if [ -f "shoply-${VERSION}-linux-amd64.tar.gz" ]; then
        TARBALL="shoply-${VERSION}-linux-amd64.tar.gz"
    else
        TARBALL=$(ls shoply-*.tar.gz 2>/dev/null | head -n 1 || true)
    fi

    if [ -n "$TARBALL" ] && [ -f "$TARBALL" ]; then
        echo "[Shoply] 检测到本地发行包 $TARBALL，正在自动解压..."
        tar -xzf "$TARBALL"
        return 0
    fi

    # 步骤 4.3：本地不存在离线包，尝试从 GitCode / GitHub Releases 自动拉取
    echo "[Shoply] 正在尝试自动从 Release 镜像源获取闭源二进制与资产包..."

    local sources=$(detect_mirror_priority)
    local target_tag="$VERSION"

    # 若版本是 latest，尝试从源 API 解析最新 tag
    if [ "$target_tag" = "latest" ]; then
        for src in $sources; do
            local found_tag=$(resolve_latest_tag "$src")
            if [ -n "$found_tag" ]; then
                echo "[Shoply] 从 $src 解析到最新发布版本: $found_tag"
                target_tag="$found_tag"
                VERSION="$found_tag"
                break
            fi
        done
    fi

    # 构造候选 tag 与文件列表
    local candidate_tags=()
    if [ "$target_tag" != "latest" ]; then
        if [[ "$target_tag" == v* ]]; then
            candidate_tags=("$target_tag" "${target_tag#v}")
        else
            candidate_tags=("v$target_tag" "$target_tag")
        fi
    else
        candidate_tags=("latest")
    fi

    local download_success=0
    local downloaded_tarball=""

    for src in $sources; do
        for t in "${candidate_tags[@]}"; do
            local filenames=(
                "shoply-${t}-linux-amd64.tar.gz"
                "shoply-linux-amd64.tar.gz"
            )
            for fname in "${filenames[@]}"; do
                if try_download_from_source "$src" "$t" "$fname"; then
                    download_success=1
                    downloaded_tarball="$fname"
                    break 3
                fi
            done
        done
    done

    if [ "$download_success" -eq 1 ] && [ -f "$downloaded_tarball" ]; then
        echo "[Shoply] 正在自动解压资产包: $downloaded_tarball ..."
        tar -xzf "$downloaded_tarball"
        return 0
    fi

    # 步骤 4.4：若自动下载与本地解压均未能就绪，输出友好帮助信息
    echo ""
    echo "======================================================================"
    echo "错误: 未能获取到运行资产包 (shoply, plugins, public, template, resource)。"
    echo ""
    echo "这通常是因为目标版本尚未发布 Release 附件，或当前处于离线/无网络环境。"
    echo "您可以选择以下任一方式运行或构建:"
    echo "  1. 直接使用官方预构建好的容器镜像 (推荐，无需本地构建或下载二进制):"
    echo "     ./scripts/shoply.sh start"
    echo ""
    echo "  2. 手动从官方 Releases 下载对应版本的 shoply-*.tar.gz 放入本目录:"
    echo "     - 国内源 (GitCode): https://gitcode.com/hoxiai/shoply/releases"
    echo "     - 海外源 (GitHub):  https://github.com/hoxiai/shoply/releases"
    echo "     放置压缩包后重新执行: ./build.sh $VERSION"
    echo ""
    echo "  3. 若您在源码工程中，可先编译打包:"
    echo "     task build:image -- $VERSION --pack"
    echo "======================================================================"
    exit 1
}

check_assets

# 5. 确定二进制与预处理工具路径
SHOPLY_BIN=""
if [ -f "shoply" ]; then
    SHOPLY_BIN="shoply"
elif [ -f "shoply-linux-amd64" ]; then
    SHOPLY_BIN="shoply-linux-amd64"
elif [ -f "dist/shoply-linux-amd64" ]; then
    SHOPLY_BIN="dist/shoply-linux-amd64"
elif [ -f "../dist/shoply-linux-amd64" ]; then
    SHOPLY_BIN="../dist/shoply-linux-amd64"
fi

SHOPLY_PREPARE_BIN=""
if [ -f "shoply-prepare" ]; then
    SHOPLY_PREPARE_BIN="shoply-prepare"
elif [ -f "shoply-prepare-linux-amd64" ]; then
    SHOPLY_PREPARE_BIN="shoply-prepare-linux-amd64"
elif [ -f "dist/shoply-prepare-linux-amd64" ]; then
    SHOPLY_PREPARE_BIN="dist/shoply-prepare-linux-amd64"
elif [ -f "../dist/shoply-prepare-linux-amd64" ]; then
    SHOPLY_PREPARE_BIN="../dist/shoply-prepare-linux-amd64"
fi

if [ -z "$SHOPLY_BIN" ]; then
    echo "[Shoply] 错误: 未找到 shoply 二进制文件。" >&2
    exit 1
fi

if [ -z "$SHOPLY_PREPARE_BIN" ]; then
    echo "[Shoply] 错误: 未找到 shoply-prepare 预处理工具。" >&2
    exit 1
fi

# 6. 执行构建
echo "[Shoply] 开始构建镜像 (SHOPLY_BINARY=$SHOPLY_BIN, PREPARE=$SHOPLY_PREPARE_BIN)..."
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

# 7. 推送（可选）
if [ "$DO_PUSH" = true ]; then
    echo "[Shoply] 正在推送镜像至 ${REGISTRY}..."
    $ENGINE push "${REGISTRY}/${IMAGE_NAME}:${VERSION}"
    $ENGINE push "${REGISTRY}/${IMAGE_NAME}:latest"
    echo "[Shoply] 镜像推送完成！"
fi
