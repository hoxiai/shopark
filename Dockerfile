# ========================================================
# Shoply 生产运行镜像构建 Dockerfile
# ========================================================
ARG SHOPLY_BASE_IMAGE=shoply-base:latest
ARG SHOPLY_PLATFORM=linux/amd64

FROM --platform=${SHOPLY_PLATFORM} ${SHOPLY_BASE_IMAGE}

ARG SHOPLY_BINARY=shoply
ARG SHOPLY_PREPARE_BINARY=shoply-prepare

WORKDIR /var/www/shoply
ENV TZ=UTC

# 1. 复制已编译好的 Go 主程序与预处理工具并赋权
COPY --chmod=755 ${SHOPLY_BINARY} ./shoply
COPY --chmod=755 ${SHOPLY_PREPARE_BINARY} /usr/local/bin/shoply-prepare

# 2. 复制核心运行依赖与静态资产
COPY plugins ./plugins
COPY resource ./resource
COPY template ./template
COPY public ./public

# 3. 复制容器入口脚本并赋权
COPY --chmod=755 scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# 4. 创建挂载与运行态目录，并备份内置应用插件供宿主机挂载时自愈释放
RUN mkdir -p data config platform runtime tenant public/uploads && \
    cp -r plugins/app /var/www/shoply/.builtin-plugins-app

EXPOSE 5490

# 5. 入口与启动
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["./shoply"]
