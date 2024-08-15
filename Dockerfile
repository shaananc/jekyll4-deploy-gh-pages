FROM ruby:3.3-alpine


RUN apk add --update-cache \
    jq \
    curl \
    vips-dev \
    libpng-dev \
    libwebp-dev \
    jpeg-dev \
    libheif-dev \
    libffi-dev \
    bash \
    git \
    gcc \
    build-base \
    openssh \
    openssl \
    openssl-dev \
    libxml2-dev \
    libxslt-dev \
    gcompat \
    vips \
    vips-tools \
    && rm -rf /var/cache/apk/*

RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq

# install a modern bundler version
RUN gem update --system
RUN gem install bundler


ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["bash","/entrypoint.sh"]
#ENTRYPOINT ["bash"]
