# Use Ubuntu as a base image
FROM ubuntu:18.04

# Environment variables
ENV encoder=x265 \
    bitdepth=10 \
    audioencoder=libopus \
    stereobitrate=128k \
    surrfiveonebitrate=384k \
    surrsevenonebitrate=512k \
    uhdcrf=20 \
    hdcrf=21 \
    sdcrf=20 \
    preset=medium \
    cropblackbars=true \
    cropscanstart=600 \
    cropscanlength=120

# Set the working directory to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
ADD . /app

RUN \
# Install dependencies
apt-get update && \
apt-get install -y \
  curl \
  mediainfo \
  xz-utils && \
# Download ffmpeg static binaries
# https://johnvansickle.com/ffmpeg/
curl -O https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz && \
tar -xf ffmpeg-git-amd64-static.tar.xz && \
cp ffmpeg-git-*-amd64-static/ffmpeg . && \
cp ffmpeg-git-*-amd64-static/ffprobe . && \
rm -rf ffmpeg-git*amd64-static* && \
# Clean up dependencies
apt-get remove -y \
  xz-utils && \
apt-get -y autoremove && \
apt-get clean && \
rm -rf /var/lib/apt/lists/* && \
# Set transcode script as executable
chmod +x /app/transcode.sh

# Run transcode.sh when the container launches
CMD ["/app/transcode.sh"]
