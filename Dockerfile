# Stage 1: Source
FROM archlinux:latest AS source
RUN pacman -Sy --noconfirm wget tar
WORKDIR /src
RUN wget -q http://www.fftw.org/fftw-3.3.10.tar.gz && \
    tar -xzf fftw-3.3.10.tar.gz

# Stage 2: Linux Build
FROM archlinux:latest AS linux-build
RUN pacman -Sy --noconfirm base-devel
WORKDIR /build
COPY --from=source /src/fftw-3.3.10 .
RUN ./configure \
        --enable-float \
        --enable-shared \
        --disable-static \
        --enable-threads \
        --with-combined-threads \
        --enable-sse \
        --enable-sse2 \
        --enable-avx \
        --enable-avx2 \
        --enable-avx-128-fma \
        --enable-pic && \
    make -j$(nproc)

# Stage 3: Windows Binaries
FROM archlinux:latest AS windows-binaries
RUN pacman -Sy --noconfirm wget unzip
WORKDIR /build
RUN wget -q https://fftw.org/pub/fftw/fftw-3.3.5-dll64.zip && \
    unzip fftw-3.3.5-dll64.zip

# Stage 4: Export
FROM scratch AS export
WORKDIR /libs
COPY --from=linux-build /build/.libs/libfftw3f.so .
COPY --from=windows-binaries /build/libfftw3f-3.dll .
