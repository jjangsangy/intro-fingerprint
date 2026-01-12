FROM mcr.microsoft.com/devcontainers/base:ubuntu-22.04

# Install MPV, FFmpeg, LuaJIT and other dependencies
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
    mpv \
    ffmpeg \
    luajit \
    libfftw3-dev \
    build-essential \
    xvfb \
    git \
    curl \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set up a fake display for headless MPV testing
ENV DISPLAY=:99

# Add entrypoint script to start Xvfb if needed
RUN echo '#!/bin/bash\nXvfb :99 -screen 0 1280x1024x24 &\nexec "$@"' > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

# Set working directory
WORKDIR /workspace
