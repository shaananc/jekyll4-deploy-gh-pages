FROM ruby:3.4

RUN apt-get update && apt-get install -y \
    libvips-dev \
    libvips-tools \
    libpng-dev \
    libwebp-dev \
    libjpeg-dev \
    libheif-dev \
    && rm -rf /var/lib/apt/lists/*

# install a modern bundler version
RUN gem update --system
RUN gem install bundler




ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
