FROM ruby:3.1

RUN apt-get update && apt-get install -y \
    libvips-dev \
    libvips-tools \
    libpng-dev \
    libwebp-dev \
    libjpeg-dev \
    libheif-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq &&\
    chmod +x /usr/bin/yq

# install a modern bundler version
RUN gem install bundler

# hack that would normally be bad but acceptable given stability of libffi
RUN ln -s $(find / -name "libffi.so.7" | head -n1) $(find / -name "libffi.so.7" | head -n1 | xargs dirname)/libffi.so.8


ADD build-version.sh /build-version.sh
ADD entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
