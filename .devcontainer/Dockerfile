FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

# Install MPV, FFmpeg, LuaJIT and basic build tools
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        alsa-utils \
        autoconf \
        automake \
        build-essential \
        curl \
        ffmpeg \
        git \
        gperf \
        libass-dev \
        libavcodec-dev \
        libavdevice-dev \
        libavfilter-dev \
        libavformat-dev \
        libavutil-dev \
        libegl1-mesa-dev \
        libepoxy-dev \
        libfontconfig1-dev \
        libfreetype6-dev \
        libfribidi-dev \
        libgl1 \
        libgl1-mesa-dev \
        libgl1-mesa-dri \
        libharfbuzz-dev \
        libluajit-5.1-dev \
        libplacebo-dev \
        libswresample-dev \
        libswscale-dev \
        libtool \
        libva-dev \
        libwayland-dev \
        libx11-dev \
        libxcursor-dev \
        libxext-dev \
        libxinerama-dev \
        libxkbcommon-dev \
        libxpresent-dev \
        libxrandr-dev \
        libxrender-dev \
        libxv-dev \
        luajit \
        mesa-utils \
        meson \
        mpv \
        nasm \
        ninja-build \
        pkg-config \
        pulseaudio-utils \
        python-is-python3 \
        python3-pip \
        wayland-protocols \
        xvfb \
        yasm \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Build MPV v0.38.0 with LuaJIT enabled
# We build against system libraries for stability and compatibility with Ubuntu 24.04
WORKDIR /tmp/mpv-src
RUN git clone https://github.com/mpv-player/mpv.git . \
    && git checkout v0.38.0 \
    && meson setup build \
        -Dlua=luajit \
        -Dvulkan=disabled \
        -Dwayland=enabled \
        --prefix=/usr/local \
    && meson compile -C build \
    && cp build/mpv /usr/local/bin/mpv-luajit \
    && rm -rf /tmp/mpv-src

# Set up a fake display for headless MPV testing
ENV DISPLAY=:99

# Add entrypoint script to start Xvfb if needed
RUN echo '#!/bin/bash\nXvfb :99 -screen 0 1280x1024x24 &\nexec "$@"' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

# Set working directory
WORKDIR /workspace
