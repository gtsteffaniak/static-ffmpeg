# bump: alpine /ALPINE_VERSION=alpine:([\d.]+)/ docker:alpine|^3
# bump: alpine link "Release notes" https://alpinelinux.org/posts/Alpine-$LATEST-released.html
ARG ALPINE_VERSION=alpine:3.21.3
FROM $ALPINE_VERSION AS builder

# Alpine Package Keeper options
ARG APK_OPTS="--repository=http://dl-cdn.alpinelinux.org/alpine/edge/testing/"

RUN apk add --no-cache $APK_OPTS \
  coreutils \
  pkgconfig \
  rust cargo cargo-c \
  openssl-dev openssl-libs-static \
  ca-certificates \
  bash \
  git \
  curl \
  build-base \
  autoconf automake \
  libtool \
  diffutils \
  cmake meson ninja \
  yasm nasm \
  texinfo \
  jq \
  zlib-dev zlib-static \
  bzip2-dev bzip2-static \
  libxml2-dev libxml2-static \
  expat-dev expat-static \
  fontconfig-dev fontconfig-static \
  freetype freetype-dev freetype-static \
  graphite2-static \
  tiff tiff-dev \
  libjpeg-turbo libjpeg-turbo-dev \
  libpng-dev libpng-static \
  giflib giflib-dev \
  fribidi-dev fribidi-static \
  brotli-dev brotli-static \
  soxr-dev soxr-static \
  tcl \
  numactl-dev \
  cunit cunit-dev \
  fftw-dev \
  libsamplerate-dev libsamplerate-static \
  vo-amrwbenc-dev vo-amrwbenc-static \
  snappy snappy-dev snappy-static \
  xxd \
  xz-dev xz-static \
  python3 py3-packaging \
  linux-headers \
  libdrm-dev

COPY [ "src/", "./" ]

# linux-headers need by rtmpdump
# python3 py3-packaging needed by glib

# -O3 makes sure we compile with optimization. setting CFLAGS/CXXFLAGS seems to override
# default automake cflags.
# -static-libgcc is needed to make gcc not include gcc_s as "as-needed" shared library which
# cmake will include as a implicit library.
# other options to get hardened build (same as ffmpeg hardened)
ARG CFLAGS="-O3 -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG CXXFLAGS="-O3 -static-libgcc -fno-strict-overflow -fstack-protector-all -fPIC"
ARG LDFLAGS="-Wl,-z,relro,-z,now"

RUN cd harfbuzz-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install

RUN cd cairo-* && \
meson setup build \
  -Dbuildtype=release \
  -Ddefault_library=static \
  -Dtests=disabled \
  -Dquartz=disabled \
  -Dxcb=disabled \
  -Dxlib=disabled \
  -Dxlib-xcb=disabled && \
ninja -j$(nproc) -vC build install

RUN cd pango-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=both \
    -Dintrospection=disabled \
    -Dgtk_doc=false && \
  ninja -j$(nproc) -vC build install

RUN cd librsvg-* && \
  # workaround for https://gitlab.gnome.org/GNOME/librsvg/-/issues/1158
  sed -i "/^if host_system in \['windows'/s/, 'linux'//" meson.build && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddocs=disabled \
    -Dintrospection=disabled \
    -Dpixbuf=disabled \
    -Dpixbuf-loader=disabled \
    -Dvala=disabled \
    -Dtests=false && \
  ninja -j$(nproc) -vC build install

RUN cd libva-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Ddisable_drm=false \
    -Dwith_x11=no \
    -Dwith_glx=no \
    -Dwith_wayland=no \
    -Dwith_win32=no \
    -Dwith_legacy=[] \
    -Denable_docs=false && \
  ninja -j$(nproc) -vC build install

RUN cd vmaf-*/libvmaf && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dbuilt_in_models=true \
    -Denable_tests=false \
    -Denable_docs=false \
    -Denable_avx512=true \
    -Denable_float=true && \
  ninja -j$(nproc) -vC build install
# extra libs stdc++ is for vmaf https://github.com/Netflix/vmaf/issues/788
RUN sed -i 's/-lvmaf /-lvmaf -lstdc++ /' /usr/local/lib/pkgconfig/libvmaf.pc

RUN cd glib-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static \
    -Dlibmount=disabled && \
  ninja -j$(nproc) -vC build install

RUN cd libass-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) && make install

# dec_init rename is to workaround https://code.videolan.org/videolan/libbluray/-/issues/43
RUN cd libbluray-* && \
  sed -i 's/dec_init/libbluray_dec_init/' src/libbluray/disc/* && \
  git clone https://code.videolan.org/videolan/libudfread.git contrib/libudfread && \
  (cd contrib/libudfread && git checkout --recurse-submodules $LIBUDFREAD_COMMIT) && \
  autoreconf -fiv && \
  ./configure \
    --with-pic \
    --disable-doxygen-doc \
    --disable-doxygen-dot \
    --enable-static \
    --disable-shared \
    --disable-examples \
    --disable-bdjava-jar && \
  make -j$(nproc) install

RUN cd aom && \
  mkdir build_tmp && cd build_tmp && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_EXAMPLES=NO \
    -DENABLE_DOCS=NO \
    -DENABLE_TESTS=NO \
    -DENABLE_TOOLS=NO \
    -DCONFIG_TUNE_VMAF=1 \
    -DENABLE_NASM=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    .. && \
  make -j$(nproc) install

RUN cd libaribb24 && \
  autoreconf -fiv && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) && make install

# TODO: seems to be issues with asm on musl
RUN cd davs2-*/build/linux && \
  ./configure \
    --disable-asm \
    --enable-pic \
    --enable-strip \
    --disable-cli && \
  make -j$(nproc) install

RUN cd fdk-aac-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd libgsm && \
  # Makefile is hard to use, hence use specific compile arguments and flags
  # no need to build toast cli tool \
  rm src/toast* && \
  SRC=$(echo src/*.c) && \
  gcc ${CFLAGS} -c -ansi -pedantic -s -DNeedFunctionPrototypes=1 -Wall -Wno-comment -DSASR -DWAV49 -DNDEBUG -I./inc ${SRC} && \
  ar cr libgsm.a *.o && ranlib libgsm.a && \
  mkdir -p /usr/local/include/gsm && \
  cp inc/*.h /usr/local/include/gsm && \
  cp libgsm.a /usr/local/lib

RUN cd kvazaar-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd lame-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --enable-nasm \
    --disable-gtktest \
    --disable-cpml \
    --disable-frontend && \
  make -j$(nproc) install

RUN cd lcms2-* && \
  ./autogen.sh && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) install

RUN cd opencore-amr-* && \
  ./configure \
    --enable-static \
    --disable-shared && \
  make -j$(nproc) install

RUN cd openjpeg-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_PKGCONFIG_FILES=ON \
    -DBUILD_CODEC=OFF \
    -DWITH_ASTYLE=OFF \
    -DBUILD_TESTING=OFF \
    .. && \
  make -j$(nproc) install

RUN cd opus-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-extra-programs \
    --disable-doc && \
  make -j$(nproc) install

RUN cd rabbitmq-c-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DBUILD_EXAMPLES=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_STATIC_LIBS=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    -DBUILD_TOOLS=OFF \
    -DBUILD_TOOLS_DOCS=OFF \
    -DRUN_SYSTEM_TESTS=OFF \
    .. && \
  make -j$(nproc) install

RUN cd rtmpdump && \
  make SYS=posix SHARED=off -j$(nproc) install

RUN cd rubberband-* && \
  meson setup build \
    -Ddefault_library=static \
    -Dfft=fftw \
    -Dresampler=libsamplerate && \
  ninja -j$(nproc) -vC build install && \
  echo "Requires.private: fftw3 samplerate" >> /usr/local/lib/pkgconfig/rubberband.pc

RUN cd shine* && \
  ./configure \
    --with-pic \
    --enable-static \
    --disable-shared \
    --disable-fast-install && \
  make -j$(nproc) install


RUN cd speex-Speex-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd libssh* && \
  mkdir build && cd build && \
  echo -e 'Requires.private: libssl libcrypto zlib \nLibs.private: -DLIBSSH_STATIC=1 -lssh\nCflags.private: -DLIBSSH_STATIC=1 -I${CMAKE_INSTALL_FULL_INCLUDEDIR}' >> ../libssh.pc.cmake && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_SYSTEM_ARCH=$(arch) \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_BUILD_TYPE=Release \
    -DPICKY_DEVELOPER=ON \
    -DBUILD_STATIC_LIB=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DWITH_GSSAPI=OFF \
    -DWITH_BLOWFISH_CIPHER=ON \
    -DWITH_SFTP=ON \
    -DWITH_SERVER=OFF \
    -DWITH_ZLIB=ON \
    -DWITH_PCAP=ON \
    -DWITH_DEBUG_CRYPTO=OFF \
    -DWITH_DEBUG_PACKET=OFF \
    -DWITH_DEBUG_CALLTRACE=OFF \
    -DUNIT_TESTING=OFF \
    -DCLIENT_TESTING=OFF \
    -DSERVER_TESTING=OFF \
    -DWITH_EXAMPLES=OFF \
    -DWITH_INTERNAL_DOC=OFF \
    .. && \
  # make -j seems to be shaky, libssh.a ends up truncated (used before fully created?)
  make install

RUN cd SVT-AV1-*/Build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_AVX512=ON \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install

# has to be before theora
RUN cd libogg-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd libtheora-* && \
  # --build=$(arch)-unknown-linux-gnu helps with guessing the correct build. For some reason,
  # build script can't guess the build type in arm64 (hardware and emulated) environment.
 ./configure \
   --disable-examples \
   --disable-oggtest \
   --disable-shared \
   --enable-static && \
  make -j$(nproc) install

RUN cd twolame-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-sndfile \
    --with-pic && \
  make -j$(nproc) install

RUN cd uavs3d && \
  mkdir build/linux && cd build/linux && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    ../.. && \
  make -j$(nproc) install

RUN cd vid.stab-* && \
  mkdir build && cd build && \
  # This line workarounds the issue that happens when the image builds in emulated (buildx) arm64 environment.
  # Since in emulated container the /proc is mounted from the host, the cmake not able to detect CPU features correctly.
  sed -i 's/include (FindSSE)/if(CMAKE_SYSTEM_ARCH MATCHES "amd64")\ninclude (FindSSE)\nendif()/' ../CMakeLists.txt && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_SYSTEM_ARCH=$(arch) \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DUSE_OMP=ON \
    .. && \
  make -j$(nproc) install
RUN echo "Libs.private: -ldl" >> /usr/local/lib/pkgconfig/vidstab.pc

RUN cd x264 && \
  ./configure \
    --enable-pic \
    --enable-static \
    --disable-cli \
    --disable-lavf \
    --disable-swscale && \
  make -j$(nproc) install

RUN cd x265_*/build/linux && \
  sed -i '/^cmake / s/$/ -G "Unix Makefiles" ${CMAKEFLAGS}/' ./multilib.sh && \
  sed -i 's/ -DENABLE_SHARED=OFF//g' ./multilib.sh && \
  MAKEFLAGS="-j$(nproc)" \
  CMAKEFLAGS="-DENABLE_SHARED=OFF -DCMAKE_VERBOSE_MAKEFILE=ON -DENABLE_AGGRESSIVE_CHECKS=ON -DENABLE_NASM=ON -DCMAKE_BUILD_TYPE=Release" \
  ./multilib.sh && \
  make -C 8bit -j$(nproc) install

RUN cd xvidcore/build/generic && \
  CFLAGS="$CFLAGS -fstrength-reduce -ffast-math" ./configure && \
  make -j$(nproc) && make install

RUN cd xeve-* && \
  sed -i 's/mc_filter_bilin/xevem_mc_filter_bilin/' src_main/sse/xevem_mc_sse.c && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DARM="$(if [ $(uname -m) == aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install && \
  ln -s /usr/local/lib/xeve/libxeve.a /usr/local/lib/libxeve.a

RUN cd xevd-* && \
  sed -i 's/mc_filter_bilin/xevdm_mc_filter_bilin/' src_main/sse/xevdm_mc_sse.c && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DARM="$(if [ $(uname -m) == aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install && \
  ln -s /usr/local/lib/xevd/libxevd.a /usr/local/lib/libxevd.a

RUN cd libjxl-* && \
  ./deps.sh && \
  cmake -B build \
    -G"Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF \
    -DJPEGXL_ENABLE_PLUGINS=OFF \
    -DJPEGXL_ENABLE_BENCHMARK=OFF \
    -DJPEGXL_ENABLE_COVERAGE=OFF \
    -DJPEGXL_ENABLE_EXAMPLES=OFF \
    -DJPEGXL_ENABLE_FUZZERS=OFF \
    -DJPEGXL_ENABLE_SJPEG=OFF \
    -DJPEGXL_ENABLE_SKCMS=OFF \
    -DJPEGXL_ENABLE_VIEWERS=OFF \
    -DJPEGXL_FORCE_SYSTEM_GTEST=ON \
    -DJPEGXL_FORCE_SYSTEM_BROTLI=ON \
    -DJPEGXL_FORCE_SYSTEM_HWY=OFF && \
  cmake --build build -j$(nproc) && \
  cmake --install build
# workaround for ffmpeg configure script
RUN \
  sed -i 's/-ljxl/-ljxl -lstdc++ /' /usr/local/lib/pkgconfig/libjxl.pc && \
  sed -i 's/-ljxl_cms/-ljxl_cms -lstdc++ /' /usr/local/lib/pkgconfig/libjxl_cms.pc && \
  sed -i 's/-ljxl_threads/-ljxl_threads -lstdc++ /' /usr/local/lib/pkgconfig/libjxl_threads.pc

RUN cd libvpl-* && \
  cmake -B build \
    -G"Unix Makefiles" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_PREFIX=/usr/local \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTS=OFF \
    -DENABLE_WARNING_AS_ERROR=ON && \
  cmake --build build -j$(nproc) && \
  cmake --install build

RUN cd vvenc-* && \
  sed -i 's/-Werror;//' source/Lib/vvenc/CMakeLists.txt && \
  cmake \
    -S . \
    -B build/release-static \
    -DVVENC_ENABLE_WERROR=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr/local && \
  cmake --build build/release-static -j && \
  cmake --build build/release-static --target install

RUN cd dav1d-* && \
  meson setup build \
    -Dbuildtype=release \
    -Ddefault_library=static && \
  ninja -j$(nproc) -vC build install


RUN cd game-music-emu && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_SHARED_LIBS=OFF \
    -DENABLE_UBSAN=OFF \
    .. && \
  make -j$(nproc) install

RUN cd libmodplug-* && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd rav1e-* && \
  # workaround weird cargo problem when on aws (?) weirdly alpine edge seems to work
  CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse" \
  RUSTFLAGS="-C target-feature=+crt-static" \
  cargo cinstall --release

RUN cd zeromq-* && \
  # fix sha1_init symbol collision with libssh
  grep -r -l sha1_init external/sha1* | xargs sed -i 's/sha1_init/zeromq_sha1_init/g' && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd zimg-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static && \
  make -j$(nproc) install

RUN cd srt-* && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_SHARED=OFF \
    -DENABLE_APPS=OFF \
    -DENABLE_CXX11=ON \
    -DUSE_STATIC_LIBSTDCXX=ON \
    -DOPENSSL_USE_STATIC_LIBS=ON \
    -DENABLE_LOGGING=OFF \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DCMAKE_INSTALL_INCLUDEDIR=include \
    -DCMAKE_INSTALL_BINDIR=bin \
    .. && \
  make -j$(nproc) && make install

RUN cd libwebp-* && \
  ./autogen.sh && \
  ./configure \
    --disable-shared \
    --enable-static \
    --with-pic \
    --enable-libwebpmux \
    --disable-libwebpextras \
    --disable-libwebpdemux \
    --disable-sdl \
    --disable-gl \
    --disable-png \
    --disable-jpeg \
    --disable-tiff \
    --disable-gif && \
  make -j$(nproc) install

RUN cd libvpx-* && \
  ./configure \
    --enable-static \
    --enable-vp9-highbitdepth \
    --disable-shared \
    --disable-unit-tests \
    --disable-examples && \
  make -j$(nproc) install

RUN cd libvorbis-* && \
  ./configure \
    --disable-shared \
    --enable-static \
    --disable-oggtest && \
  make -j$(nproc) install

RUN cd libmysofa-*/build && \
  cmake \
    -G"Unix Makefiles" \
    -DCMAKE_VERBOSE_MAKEFILE=ON \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DBUILD_SHARED_LIBS=OFF \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTS=OFF \
    .. && \
  make -j$(nproc) install

# sed changes --toolchain=hardened -pie to -static-pie
#
# ldflags stack-size=2097152 is to increase default stack size from 128KB (musl default) to something
# more similar to glibc (2MB). This fixing segfault with libaom-av1 and libsvtav1 as they seems to pass
# large things on the stack.
#
# --enable-small to optimize for smaller size of the ffmpeg binary.
#
# ldfalgs -Wl,--allow-multiple-definition is a workaround for linking with multiple rust staticlib to
# not cause collision in toolchain symbols, see comment in checkdupsym script for details.
RUN cd ffmpeg* && \
  # workaround for https://gitlab.com/AOMediaCodec/SVT-AV1/-/merge_requests/2387
  sed -i 's/svt_av1_enc_init_handle(&svt_enc->svt_handle, svt_enc, &svt_enc->enc_params)/svt_av1_enc_init_handle(\&svt_enc->svt_handle, \&svt_enc->enc_params)/g' libavcodec/libsvtav1.c && \
  FDKAAC_FLAGS=$(if [[ -n "$ENABLE_FDKAAC" ]] ;then echo " --enable-libfdk-aac --enable-nonfree " ;else echo ""; fi) && \
  sed -i 's/add_ldexeflags -fPIE -pie/add_ldexeflags -fPIE -static-pie/' configure && \
  ./configure \
  --pkg-config-flags="--static" \
  --extra-cflags="-fopenmp" \
  --extra-ldflags="-fopenmp -Wl,--allow-multiple-definition -Wl,-z,stack-size=2097152" \
  --toolchain=hardened \
  --disable-debug \
  --disable-shared \
  --disable-ffplay \
  --enable-static \
  --enable-gpl \
  --enable-version3 \
  $FDKAAC_FLAGS \
  --enable-fontconfig \
  --enable-gray \
  --enable-iconv \
  --enable-lcms2 \
  --enable-libaom \
  --enable-libaribb24 \
  --enable-libass \
  --enable-libbluray \
  --enable-libdav1d \
  --enable-libdavs2 \
  --enable-libfreetype \
  --enable-libfribidi \
  --enable-libgme \
  --enable-libgsm \
  --enable-libharfbuzz \
  --enable-libjxl \
  --enable-libkvazaar \
  --enable-libmodplug \
  --enable-libmp3lame \
  --enable-libmysofa \
  --enable-libopencore-amrnb \
  --enable-libopencore-amrwb \
  --enable-libopenjpeg \
  --enable-libopus \
  --enable-librabbitmq \
  --enable-librav1e \
  --enable-librsvg \
  --enable-librtmp \
  --enable-librubberband \
  --enable-libshine \
  --enable-libsnappy \
  --enable-libsoxr \
  --enable-libspeex \
  --enable-libsrt \
  --enable-libssh \
  --enable-libsvtav1 \
  --enable-libtheora \
  --enable-libtwolame \
  --enable-libuavs3d \
  --enable-libvidstab \
  --enable-libvmaf \
  --enable-libvo-amrwbenc \
  --enable-libvorbis \
  --enable-libvpl \
  --enable-libvpx \
  --enable-libvvenc \
  --enable-libwebp \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libxevd \
  --enable-libxeve \
  --enable-libxml2 \
  --enable-libxvid \
  --enable-libzimg \
  --enable-libzmq \
  --enable-small \
  --enable-openssl \
  || (cat ffbuild/config.log ; false) \
  && make -j$(nproc) install

RUN \
  EXPAT_VERSION=$(pkg-config --modversion expat) \
  FFTW_VERSION=$(pkg-config --modversion fftw3) \
  FONTCONFIG_VERSION=$(pkg-config --modversion fontconfig) \
  FREETYPE_VERSION=$(pkg-config --modversion freetype2) \
  FRIBIDI_VERSION=$(pkg-config --modversion fribidi) \
  LIBSAMPLERATE_VERSION=$(pkg-config --modversion samplerate) \
  LIBVO_AMRWBENC_VERSION=$(pkg-config --modversion vo-amrwbenc) \
  LIBXML2_VERSION=$(pkg-config --modversion libxml-2.0) \
  OPENSSL_VERSION=$(pkg-config --modversion openssl) \
  SNAPPY_VERSION=$(apk info -a snappy $APK_OPTS | head -n1 | awk '{print $1}' | sed -e 's/snappy-//') \
  SOXR_VERSION=$(pkg-config --modversion soxr) \
  jq -n \
  '{ \
  expat: env.EXPAT_VERSION, \
  "libfdk-aac": env.FDK_AAC_VERSION, \
  ffmpeg: env.FFMPEG_VERSION, \
  fftw: env.FFTW_VERSION, \
  fontconfig: env.FONTCONFIG_VERSION, \
  lcms2: env.LCMS2_VERSION, \
  libaom: env.AOM_VERSION, \
  libaribb24: env.LIBARIBB24_VERSION, \
  libass: env.LIBASS_VERSION, \
  libbluray: env.LIBBLURAY_VERSION, \
  libdav1d: env.DAV1D_VERSION, \
  libdavs2: env.DAVS2_VERSION, \
  libfreetype: env.FREETYPE_VERSION, \
  libfribidi: env.FRIBIDI_VERSION, \
  libgme: env.LIBGME_COMMIT, \
  libgsm: env.LIBGSM_COMMIT, \
  libharfbuzz: env.LIBHARFBUZZ_VERSION, \
  libjxl: env.LIBJXL_VERSION, \
  libkvazaar: env.KVAZAAR_VERSION, \
  libmodplug: env.LIBMODPLUG_VERSION, \
  libmp3lame: env.MP3LAME_VERSION, \
  libmysofa: env.LIBMYSOFA_VERSION, \
  libogg: env.OGG_VERSION, \
  libopencoreamr: env.OPENCOREAMR_VERSION, \
  libopenjpeg: env.OPENJPEG_VERSION, \
  libopus: env.OPUS_VERSION, \
  librabbitmq: env.LIBRABBITMQ_VERSION, \
  librav1e: env.RAV1E_VERSION, \
  librsvg: env.LIBRSVG_VERSION, \
  librtmp: env.LIBRTMP_COMMIT, \
  librubberband: env.RUBBERBAND_VERSION, \
  libsamplerate: env.LIBSAMPLERATE_VERSION, \
  libshine: env.LIBSHINE_VERSION, \
  libsnappy: env.SNAPPY_VERSION, \
  libsoxr: env.SOXR_VERSION, \
  libspeex: env.SPEEX_VERSION, \
  libsrt: env.SRT_VERSION, \
  libssh: env.LIBSSH_VERSION, \
  libsvtav1: env.SVTAV1_VERSION, \
  libtheora: env.THEORA_VERSION, \
  libtwolame: env.TWOLAME_VERSION, \
  libuavs3d: env.UAVS3D_COMMIT, \
  libva: env.LIBVA_VERSION, \
  libvidstab: env.VIDSTAB_VERSION, \
  libvmaf: env.VMAF_VERSION, \
  libvo_amrwbenc: env.LIBVO_AMRWBENC_VERSION, \
  libvorbis: env.VORBIS_VERSION, \
  libvpl: env.LIBVPL_VERSION, \
  libvpx: env.VPX_VERSION, \
  libvvenc: env.VVENC_VERSION, \
  libwebp: env.LIBWEBP_VERSION, \
  libx264: env.X264_VERSION, \
  libx265: env.X265_VERSION, \
  libxavs2: env.XAVS2_VERSION, \
  libxevd: env.XEVD_VERSION, \
  libxeve: env.XEVE_VERSION, \
  libxml2: env.LIBXML2_VERSION, \
  libxvid: env.XVID_VERSION, \
  libzimg: env.ZIMG_VERSION, \
  libzmq: env.LIBZMQ_VERSION, \
  openssl: env.OPENSSL_VERSION, \
  }' > /versions.json

# make sure binaries has no dependencies, is relro, pie and stack nx
COPY checkelf /
RUN \
  /checkelf /usr/local/bin/ffmpeg && \
  /checkelf /usr/local/bin/ffprobe
# workaround for using -Wl,--allow-multiple-definition
# see comment in checkdupsym for details
COPY checkdupsym /
RUN /checkdupsym /ffmpeg-*

# some basic fonts that don't take up much space
RUN apk add $APK_OPTS font-terminus font-inconsolata font-dejavu font-awesome

FROM scratch AS testing
COPY --from=builder /usr/local/bin/ffmpeg /
COPY --from=builder /usr/local/bin/ffprobe /
COPY --from=builder /versions.json /
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/

# sanity tests
RUN ["/ffmpeg", "-version"]
RUN ["/ffprobe", "-version"]
RUN ["/ffmpeg", "-hide_banner", "-buildconf"]
# stack size
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libsvtav1", "-t", "100ms", "-f", "null", "-"]
# dns
RUN ["/ffprobe", "-i", "https://github.com/favicon.ico"]
# tls/https certs
RUN ["/ffprobe", "-tls_verify", "1", "-ca_file", "/etc/ssl/cert.pem", "-i", "https://github.com/favicon.ico"]
# svg
RUN ["/ffprobe", "-i", "https://github.githubassets.com/favicons/favicon.svg"]
# vvenc
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libvvenc", "-t", "100ms", "-f", "null", "-"]
# x265 regression
RUN ["/ffmpeg", "-f", "lavfi", "-i", "testsrc", "-c:v", "libx265", "-t", "100ms", "-f", "null", "-"]

FROM scratch
COPY --from=builder /usr/local/bin/ffmpeg /
COPY --from=builder /usr/local/bin/ffprobe /
COPY --from=builder /versions.json /
COPY --from=builder /usr/local/share/doc/ffmpeg/* /doc/
COPY --from=builder /etc/ssl/cert.pem /etc/ssl/cert.pem
COPY --from=builder /etc/fonts/ /etc/fonts/
COPY --from=builder /usr/share/fonts/ /usr/share/fonts/
COPY --from=builder /usr/share/consolefonts/ /usr/share/consolefonts/
COPY --from=builder /var/cache/fontconfig/ /var/cache/fontconfig/

LABEL maintainer="Mattias Wadman mattias.wadman@gmail.com"
ENTRYPOINT ["/ffmpeg"]
