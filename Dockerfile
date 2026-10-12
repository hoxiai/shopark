# ==========================================
# Shoply 生产镜像（单文件构建，不再依赖外部 shoply-base 基础镜像）
# 运行环境与代码同仓定版；runtime 层只在本段变化时重建，其余时间命中构建缓存。
# ==========================================
ARG PHP_IMAGE=php:8.2-cli-alpine3.24
ARG COMPOSER_IMAGE=composer:2.10

FROM ${COMPOSER_IMAGE} AS composer

# ==========================================
# 运行环境：PHP 扩展 + node（Site SSR）+ composer（构建期与运行时安装应用依赖）
# Go 二进制为 CGO_ENABLED=0 静态编译，不需要 glibc 兼容层。
# ==========================================
FROM ${PHP_IMAGE} AS runtime
# 可选 apk 镜像源，如 https://mirrors.aliyun.com；留空使用官方源
ARG APK_MIRROR=
# 与 plugins/composer.lock 中 google/protobuf 的大版本、小版本保持一致
ARG PROTOBUF_VERSION=4.33.6

RUN set -eux; \
    if [ -n "$APK_MIRROR" ]; then \
        sed -i -E "s#https?://dl-cdn.alpinelinux.org#${APK_MIRROR%/}#g" /etc/apk/repositories; \
    fi; \
    apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS linux-headers \
        freetype-dev icu-dev libjpeg-turbo-dev libpng-dev libwebp-dev libzip-dev zlib-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(getconf _NPROCESSORS_ONLN)" \
        bcmath gd intl opcache pcntl pdo_mysql sockets zip; \
    pecl install "protobuf-${PROTOBUF_VERSION}"; \
    docker-php-ext-enable protobuf; \
    # 只保留扩展实际链接的共享库，与官方 PHP 镜像的做法一致
    runDeps="$( \
        scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
        | tr ',' '\n' | sort -u \
        | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
    )"; \
    apk add --no-cache --virtual .shoply-phpext-rundeps $runDeps; \
    apk del --no-network .build-deps; \
    rm -rf /tmp/pear ~/.pearrc /usr/local/lib/php/test /usr/local/lib/php/doc; \
    apk add --no-cache bash nodejs tzdata; \
    php -m | grep -qi '^protobuf$'; \
    node -v

COPY --from=composer /usr/bin/composer /usr/bin/composer
ENV TZ=UTC

# ==========================================
# PHP 生产依赖
# 开发机的 vendor 带着 phpunit 等开发包，autoload 也引用它们；只靠 .dockerignore 删目录，
# autoload 仍会去加载被删掉的文件，PHP 一启动就 Fatal。这里按 composer.lock 去掉开发包并
# 重新生成 autoload。vendor 与 lock 一致时不联网。
# ==========================================
FROM runtime AS plugins
WORKDIR /build
COPY plugins ./
RUN COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --no-interaction --no-progress --no-plugins --no-scripts

# ==========================================
# 最终运行镜像
# ==========================================
FROM runtime
ARG SHOPLY_BINARY=dist/shoply-linux-amd64
ARG SHOPLY_PREPARE_BINARY=dist/shoply-prepare-linux-amd64

WORKDIR /var/www/shoply

# 1. 复制宿主机编译好的 Go 主程序并赋权
COPY --chmod=755 ${SHOPLY_BINARY} ./shoply
COPY --chmod=755 ${SHOPLY_PREPARE_BINARY} /usr/local/bin/shoply-prepare

# 2. 复制核心运行依赖与资产
COPY --from=plugins /build ./plugins
COPY resource ./resource
COPY template ./template
COPY dist/admin ./dist/admin
COPY dist/site ./dist/site
COPY public ./public

# 3. 复制容器入口脚本并赋予执行权限
COPY --chmod=755 scripts/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

# 4. 预创建运行态与挂载点目录，并备份内置应用插件供宿主机挂载时自愈释放
RUN mkdir -p data config platform runtime tenant public/uploads && \
    cp -r plugins/app /var/www/shoply/.builtin-plugins-app

EXPOSE 5490

# 5. 入口与主程序启动
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["./shoply"]
