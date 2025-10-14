FROM alpine:latest

RUN apk add --no-cache \
    bash \
    curl \
    openssl \
    docker-cli \
    docker-cli-compose \
    ca-certificates \
    sudo

WORKDIR /test

CMD ["/bin/bash"]
