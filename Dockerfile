# Use Ubuntu 16.04 as a base image
FROM ubuntu:16.04

# Set the working directory to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
ADD . /app

# Update and install dependencies
RUN \

apt-get update && \
apt-get install -y \
  curl \
  autoconf \
  automake \
  build-essential \
  libass-dev \
  libfreetype6-dev \
  libsdl1.2-dev \
  libtheora-dev \
  libtool \
  libva-dev \
  libvdpau-dev \
  libvorbis-dev \
  libxcb1-dev \
  libxcb-shm0-dev \
  libxcb-xfixes0-dev \
  pkg-config \
  texinfo \
  zlib1g-dev \
  git \
  mercurial \
  cmake \
  yasm && \

# Setup directories
mkdir -p /input /output /ffmpeg/ffmpeg_sources /ffmpeg/bin && \

# Compile and install ffmpeg and ffprobe
cd /ffmpeg/ffmpeg_sources && \
curl -O http://www.nasm.us/pub/nasm/releasebuilds/2.13.01/nasm-2.13.01.tar.xz && \
tar -xf nasm-2.13.01.tar.xz && \
git clone https://github.com/xiph/opus.git && \
git clone --depth=1 git://git.videolan.org/x264 && \
hg clone https://bitbucket.org/multicoreware/x265 && \
git clone --depth=1 https://github.com/FFmpeg/FFmpeg.git ffmpeg && \
cd ffmpeg && \
curl -O https://trac.ffmpeg.org/raw-attachment/ticket/5718/0001-libavcodec-libopusenc.c-patch-channel_layouts-back-i.patch && \

cd /ffmpeg/ffmpeg_sources/nasm-2.13.01 && \
./autogen.sh && \
PATH="/ffmpeg/bin:$PATH" ./configure --prefix="/ffmpeg/ffmpeg_build" --bindir="/ffmpeg/bin" && \
PATH="/ffmpeg/bin:$PATH" make && \
make install && \

cd /ffmpeg/ffmpeg_sources/opus && \
./autogen.sh && \
./configure --prefix="/ffmpeg/ffmpeg_build" --disable-shared && \
PATH="/ffmpeg/bin:$PATH" make && \
make install && \

cd /ffmpeg/ffmpeg_sources/x264 && \
PATH="/ffmpeg/bin:$PATH" ./configure --prefix="/ffmpeg/ffmpeg_build" --bindir="/ffmpeg/bin" --enable-pic --enable-shared --enable-static --disable-opencl && \
PATH="/ffmpeg/bin:$PATH" make && \
make install && \
make distclean && \

cd /ffmpeg/ffmpeg_sources/x265/build/linux && \
PATH="/ffmpeg/bin:$PATH" cmake -G "Unix Makefiles" -DCMAKE_INSTALL_PREFIX="/ffmpeg/ffmpeg_build" -DENABLE_SHARED:bool=off ../../source && \
make && \
make install && \

cd /ffmpeg/ffmpeg_sources/ffmpeg && \
# Apply patch to fix libopus channel mappings
# See https://trac.ffmpeg.org/ticket/5718
git apply 0001-libavcodec-libopusenc.c-patch-channel_layouts-back-i.patch && \
PATH="/ffmpeg/bin:$PATH" PKG_CONFIG_PATH="/ffmpeg/ffmpeg_build/lib/pkgconfig" ./configure \
--prefix="/ffmpeg/ffmpeg_build" \
--pkg-config-flags="--static" \
--extra-cflags="-I/ffmpeg/ffmpeg_build/include -static" \
--extra-ldflags="-L/ffmpeg/ffmpeg_build/lib -static" \
--bindir="/ffmpeg/bin" \
--enable-static \
--disable-shared \
--enable-ffprobe \
--disable-ffserver \
--enable-gpl \
--enable-libopus \
--enable-libx264 \
--enable-libx265 && \
PATH="/ffmpeg/bin:$PATH" make && \
make install && \
make distclean && \
hash -r && \

# Copy ffmpeg and ffprobe to app directory
cp /ffmpeg/bin/ff* /app/ && \

# Clean up directories and packages after compilation
rm -rf /ffmpeg && \
apt-get remove -y \
  autoconf \
  automake \
  build-essential \
  libass-dev \
  libfreetype6-dev \
  libsdl1.2-dev \
  libtheora-dev \
  libtool \
  libva-dev \
  libvdpau-dev \
  libvorbis-dev \
  libxcb1-dev \
  libxcb-shm0-dev \
  libxcb-xfixes0-dev \
  pkg-config \
  texinfo \
  zlib1g-dev \
  git \
  mercurial \
  cmake \
  yasm && \
apt-get -y autoremove && \
apt-get clean && \

# Set transcode script as executable
chmod +x /app/transcode.sh

# Environment variables
ENV encoder=x265 \
    audioencoder=libopus \
    hdcrf=21 \
    sdcrf=21 \
    preset=medium \
    cropblackbars=true \
    cropscanstart=600 \
    cropscanlength=120 \
    slackurl=https://127.0.0.1

# Run transcode.sh when the container launches
CMD ["/app/transcode.sh"]
