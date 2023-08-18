# syntax=docker/dockerfile:1

FROM alpine:3.17 as rootfs-stage

# environment
ENV REL=jammy
ENV ARCH=amd64

# install packages
RUN \
  apk add --no-cache \
    bash \
    curl \
    tzdata \
    xz

# set version for s6 overlay
ARG S6_OVERLAY_VERSION="3.1.5.0"
ARG S6_OVERLAY_ARCH="x86_64"

# add s6 overlay
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN mkdir /root-out && tar -C /root-out -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-${S6_OVERLAY_ARCH}.tar.xz

# add s6 optional symlinks
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-noarch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-symlinks-arch.tar.xz /tmp
RUN tar -C /root-out -Jxpf /tmp/s6-overlay-symlinks-arch.tar.xz


FROM texlive/texlive:latest-full
COPY --from=rootfs-stage /root-out/ /


# set version label
ARG BUILD_DATE
ARG VERSION
ARG CODE_RELEASE
ARG MODS_VERSION="v3"
ARG PKG_INST_VERSION="v1"
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="aptalca"

ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/docker-mods.${MODS_VERSION}" "/docker-mods"
ADD --chmod=744 "https://raw.githubusercontent.com/linuxserver/docker-mods/mod-scripts/package-install.${PKG_INST_VERSION}" "/etc/s6-overlay/s6-rc.d/init-mods-package-install/run"

# set environment variables
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/root" \
  LANGUAGE="en_US.UTF-8" \
  LANG="en_US.UTF-8" \
  TERM="xterm" \
  S6_CMD_WAIT_FOR_SERVICES_MAXTIME="0" \
  S6_VERBOSITY=1 \
  S6_STAGE2_HOOK=/docker-mods \
  VIRTUAL_ENV=/lsiopy \
  PATH="/lsiopy/bin:$PATH"

RUN \
  echo "**** Ripped from Ubuntu Docker Logic ****" && \
  set -xe && \
  echo '#!/bin/sh' \
    > /usr/sbin/policy-rc.d && \
  echo 'exit 101' \
    >> /usr/sbin/policy-rc.d && \
  chmod +x \
    /usr/sbin/policy-rc.d && \
  dpkg-divert --local --rename --add /sbin/initctl && \
  cp -a \
    /usr/sbin/policy-rc.d \
    /sbin/initctl && \
  sed -i \
    's/^exit.*/exit 0/' \
    /sbin/initctl && \
  echo 'force-unsafe-io' \
    > /etc/dpkg/dpkg.cfg.d/docker-apt-speedup && \
  echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
    > /etc/apt/apt.conf.d/docker-clean && \
  echo 'APT::Update::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true"; };' \
    >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Dir::Cache::pkgcache ""; Dir::Cache::srcpkgcache "";' \
    >> /etc/apt/apt.conf.d/docker-clean && \
  echo 'Acquire::Languages "none";' \
    > /etc/apt/apt.conf.d/docker-no-languages && \
  echo 'Acquire::GzipIndexes "true"; Acquire::CompressionTypes::Order:: "gz";' \
    > /etc/apt/apt.conf.d/docker-gzip-indexes && \
  echo 'Apt::AutoRemove::SuggestsImportant "false";' \
    > /etc/apt/apt.conf.d/docker-autoremove-suggests && \
  mkdir -p /run/systemd && \
  echo 'docker' \
    > /run/systemd/container && \
  echo "**** install apt-utils and locales ****" && \
  apt-get update && \
  apt-get install -y \
    apt-utils \
    locales && \
  echo "**** install packages ****" && \
  apt-get install -y \
    curl \
    gnupg \
    jq \
    netcat-traditional \
    tzdata && \
  echo "**** generate locale ****" && \
  locale-gen en_US.UTF-8 && \
  echo "**** create abc user and make our folders ****" && \
  useradd -u 911 -U -d /config -s /bin/false abc && \
  usermod -G users abc && \
  mkdir -p \
    /app \
    /config \
    /extensions \
    /defaults \
    /lsiopy && \
  chown abc /extensions && \
  echo "**** cleanup ****" && \
  apt-get autoremove && \
  apt-get clean && \
  rm -rf \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/* \
    /var/log/*

# add local files
COPY docker-baseimage-ubuntu/root/ /

ENTRYPOINT ["/init"]


# environment settings
ARG DEBIAN_FRONTEND="noninteractive"
ENV HOME="/config"

RUN \
  echo "**** install runtime dependencies ****" && \
  apt-get update && \
  apt-get install -y \
    git \
    jq \
    libatomic1 \
    nano \
    net-tools \
    sudo && \
  git config --global credential.helper store && \
  echo "**** install code-server ****" && \
  if [ -z ${CODE_RELEASE+x} ]; then \
    CODE_RELEASE=$(curl -sX GET https://api.github.com/repos/coder/code-server/releases/latest \
      | awk '/tag_name/{print $4;exit}' FS='[""]' | sed 's|^v||'); \
  fi && \
  mkdir -p /app/code-server && \
  curl -o \
    /tmp/code-server.tar.gz -L \
    "https://github.com/coder/code-server/releases/download/v${CODE_RELEASE}/code-server-${CODE_RELEASE}-linux-amd64.tar.gz" && \
  tar xf /tmp/code-server.tar.gz -C \
    /app/code-server --strip-components=1 && \
  echo "**** clean up ****" && \
  apt-get clean && \
  rm -rf \
    /config/* \
    /tmp/* \
    /var/lib/apt/lists/* \
    /var/tmp/*

# add local files
COPY /root /

# install latex workshop extension
RUN install-extension-simple James-Yu.latex-workshop && \
  install-extension-simple JeffersonQin.latex-snippets-jeff && \
  install-extension-simple stkb.rewrap && \
  install-extension-simple valentjn.vscode-ltex && \
  install-extension-simple eamodio.gitlens && \
  rm -rf /config/*

# ports and volumes
EXPOSE 8443
