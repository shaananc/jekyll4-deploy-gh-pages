FROM ruby:3.3-slim


RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    jq \
    curl \
    libvips42 \
    libvips-dev \
    libvips-tools \
    libpng-dev \
    libwebp-dev \
    libjpeg-dev \
    libheif-dev \
    libffi-dev \
    bash \
    git \
    gcc \
    g++ \
    make \
    openssh-client \
    openssl \
    libxml2-dev \
    libxslt-dev \
    ca-certificates \
    wget \
    xz-utils \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq

# install a modern bundler version
RUN gem update --system
RUN gem install bundler


ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["bash","/entrypoint.sh"]
