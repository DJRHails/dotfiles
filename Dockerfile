FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -qqy --no-install-recommends \
    bash \
    curl \
    git \
    build-essential \
    sudo \
    locales \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

RUN useradd -m -s /bin/bash dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER dev
WORKDIR /home/dev

# .dockerignore must exclude all glassine-covered paths (see .gitattributes) — the tree is decrypted.
COPY --chown=dev:dev . .files/

RUN cd .files && ./bootstrap.sh --cli --yes

SHELL ["/bin/zsh", "-l", "-c"]
CMD ["zsh"]
