FROM ruby:3.1.3-alpine3.17

RUN apk add --update-cache \
    vips \
    libpng \
    libwebp \
    libjpeg \
    libheif \
    libffi \
    bash \
    git \
    gcc \
    build-base \
    openssh \
    && rm -rf /var/cache/apk/*

RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq

# install a modern bundler version
RUN gem install bundler


ADD build-version.sh /build-version.sh
ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["bash","/entrypoint.sh"]
