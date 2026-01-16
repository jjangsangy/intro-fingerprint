# Stage 1: Source
FROM archlinux:latest AS source
RUN pacman -Sy --noconfirm wget
WORKDIR /src
RUN wget -q https://gitlab.mpcdf.mpg.de/mtr/pocketfft/-/raw/cpp/pocketfft_hdronly.h

# Stage 2: Linux Build
FROM quay.io/pypa/manylinux2014_x86_64 AS linux-build
WORKDIR /build
COPY --from=source /src/pocketfft_hdronly.h .
COPY build/pocketfft_wrapper.cpp .
RUN g++ -O3 -shared -fPIC -std=c++11 pocketfft_wrapper.cpp -o libpocketfft.so

# Stage 3: Windows Build
FROM archlinux:latest AS windows-build
RUN pacman -Sy --noconfirm base-devel mingw-w64-gcc
WORKDIR /build
COPY --from=source /src/pocketfft_hdronly.h .
COPY build/pocketfft_wrapper.cpp .
RUN x86_64-w64-mingw32-g++ -O3 -shared -static -std=c++11 pocketfft_wrapper.cpp \
    -static-libgcc -static-libstdc++ -lpthread \
    -o libpocketfft.dll

# Stage 4: MacOS M-series Build
FROM archlinux:latest AS macos-arm64-build
RUN pacman -Sy --noconfirm base-devel zig
WORKDIR /build
COPY --from=source /src/pocketfft_hdronly.h .
COPY build/pocketfft_wrapper.cpp .
RUN zig c++ -target aarch64-macos -O3 -shared -std=c++11 pocketfft_wrapper.cpp -o libpocketfft.dylib

# Stage 5: Export
FROM scratch AS export
WORKDIR /libs
COPY --from=linux-build /build/libpocketfft.so .
COPY --from=windows-build /build/libpocketfft.dll .
COPY --from=macos-arm64-build /build/libpocketfft.dylib .
