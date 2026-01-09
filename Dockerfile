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
RUN ./configure --enable-float --enable-shared --disable-static --enable-threads --enable-sse2 --enable-avx --enable-avx2 --enable-avx-128-fma --enable-pic && \
    make -j$(nproc)

# Stage 3: Windows Build
FROM archlinux:latest AS windows-build
RUN pacman -Sy --noconfirm base-devel mingw-w64-gcc
WORKDIR /build
COPY --from=source /src/fftw-3.3.10 .
# MinGW cross-compilation matching BUILD-MINGW64.sh
RUN mkdir build-mingw64 && cd build-mingw64 && \
    ../configure --prefix=/build/mingw64 \
            --host=x86_64-w64-mingw32 \
            --disable-alloca \
            --with-our-malloc16 \
            --with-windows-f77-mangling \
            --enable-shared \
            --disable-static \
            --enable-threads \
            --with-combined-threads \
            --enable-sse2 \
            --enable-avx \
            --enable-float && \
    make -j$(nproc) && \
    make install

# Stage 4: Export
FROM scratch AS export
WORKDIR /libs
COPY --from=linux-build /build/.libs/libfftw3f.so .
COPY --from=windows-build /build/mingw64/bin/libfftw3f-3.dll .
