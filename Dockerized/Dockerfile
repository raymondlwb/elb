FROM alpine:edge
MAINTAINER CMGS ilskdw@gmail.com (@CMGS1988)

ENV GVERSION 2.25-r0
ADD qinghua-apk-repositories /etc/apk/repositories
RUN apk --update add --quiet tzdata sudo ca-certificates curl
RUN curl -L https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GVERSION/glibc-$GVERSION.apk -o glibc-$GVERSION.apk && \
    curl -L https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GVERSION/glibc-bin-$GVERSION.apk -o glibc-bin-$GVERSION.apk && \
    curl -L https://github.com/sgerrand/alpine-pkg-glibc/releases/download/$GVERSION/glibc-i18n-$GVERSION.apk -o glibc-i18n-$GVERSION.apk
RUN apk add --allow-untrusted glibc-$GVERSION.apk glibc-bin-$GVERSION.apk glibc-i18n-$GVERSION.apk && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime && \
    /usr/glibc-compat/bin/localedef -c --force --quiet -i zh_CN -f UTF-8 zh_CN.UTF-8 && \
    echo "export LANG=zh_CN.UTF-8" > /etc/profile.d/locale.sh && \
    apk del glibc-i18n && \
    rm -rf glibc*.apk && \
    rm -rf /var/cache/apk/*
ADD useradd /usr/sbin/
ENV LESSCHARSET "utf-8"
ENV LANG "zh_CN.UTF-8"
ENV LC_ALL "zh_CN.UTF-8"

ENV OVERSION 1.11.2.2
RUN apk --update add build-base cmake clang tar wget perl pcre-dev openssl openssl-dev zlib zlib-dev python python-dev py2-pip py2-cffi openssl-dev openssl gcc musl-dev git
RUN wget https://openresty.org/download/openresty-$OVERSION.tar.gz && \
    wget https://github.com/yzprofile/ngx_http_dyups_module/archive/master.zip && \
    tar xvf openresty-$OVERSION.tar.gz && \
    unzip master.zip && \
    rm -rf openresty-$OVERSION.tar.gz master.zip && \
    mv ngx_http_dyups_module-master ngx_http_dyups_module
RUN cd openresty-$OVERSION/ && \
    ./configure --with-http_realip_module --add-module=../ngx_http_dyups_module
ADD ngx_http_special_response.c /openresty-$OVERSION/build/nginx-1.11.2/src/http/
RUN cd openresty-$OVERSION/ && \
    make && \
    make install && \
    ln -s /usr/local/openresty/nginx/sbin/nginx /usr/bin/nginx && \
    apk del --purge build-base clang cmake perl tar wget && \
    rm -rf /ngx_* /openresty* /var/cache/apk/*
