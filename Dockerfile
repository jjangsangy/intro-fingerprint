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
        --enable-avx-512 \
        --enable-pic && \
    make -j$(nproc)

# Stage 3: Windows Build
FROM archlinux:latest AS windows-build
RUN pacman -Sy --noconfirm base-devel git wget mingw-w64-gcc cmake ninja
WORKDIR /build
COPY --from=source /src/fftw-3.3.10 .
COPY build/ .
RUN \
    patch -Nbp1 -i 0001-detect-arm64-counter.patch && \
    patch -Nbp1 -i 0002-no-dllexport.patch && \
    patch -Nbp1 -i 0003-shared-lib.patch && \
    mkdir build-mingw && cd build-mingw && \
    cmake \
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
        -DCMAKE_SYSTEM_NAME=Windows \
        -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
        -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++ \
        -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres \
        -DCMAKE_FIND_ROOT_PATH=/usr/x86_64-w64-mingw32 \
        -Wno-dev \
        -GNinja \
        -DENABLE_FLOAT=ON \
        -DENABLE_SSE=ON -DENABLE_SSE2=ON -DENABLE_AVX=ON -DENABLE_AVX2=ON \
        -DCMAKE_INSTALL_PREFIX=/usr/x86_64-w64-mingw32 \
        -DBUILD_SHARED_LIBS=ON \
        -DENABLE_OPENMP=ON \
        -DENABLE_THREADS=ON \
        .. && \
    ../configure \
        --prefix=/usr/x86_64-w64-mingw32 \
        --build=x86_64-pc-linux-gnu \
        --host=x86_64-w64-mingw32 \
        --enable-sse2 --enable-avx --enable-avx-128-fma --enable-avx2 --enable-avx512 \
        --enable-float \
        --enable-static \
        --enable-shared \
        --enable-threads \
        --enable-openmp \
        --with-our-malloc \
        --with-g77-wrappers \
        --with-windows-f77-mangling && \
    make -j$(nproc) && \
    make install DESTDIR=/install

# Stage 4: Export
FROM scratch AS export
WORKDIR /libs
COPY --from=linux-build /build/.libs/libfftw3f.so .
COPY --from=windows-build /install/usr/x86_64-w64-mingw32/bin/libfftw3f-3.dll .
