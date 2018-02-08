# Use five82/ffmpeg as a parent image
FROM five82/ffmpeg

# Environment variables
ENV encoder=x265 \
    audioencoder=libopus \
    uhdcrf=21 \
    hdcrf=21 \
    sdcrf=20 \
    preset=medium \
    cropblackbars=true \
    cropscanstart=600 \
    cropscanlength=120 \
    slackurl=https://127.0.0.1

# Set the working directory to /app
WORKDIR /app

# Copy the current directory contents into the container at /app
ADD . /app

RUN \
# Install dependencies
apt-get update && \
apt-get install -y --no-install-recommends lsb-release wget && \
sh -c 'echo "deb http://mkvtoolnix.download/ubuntu/$(lsb_release -sc)/ ./" >> /etc/apt/sources.list.d/bunkus.org.list' && \
wget -q -O - https://mkvtoolnix.download/gpg-pub-moritzbunkus.txt | apt-key add - && \
apt-get update && \
apt-get install -y --no-install-recommends mkvtoolnix && \
apt-get remove -y lsb-release wget && \
apt-get -y autoremove && \
apt-get clean && \
rm -rf /var/lib/apt/lists/* && \
# Set transcode script as executable
chmod +x /app/transcode.sh

# Run transcode.sh when the container launches
CMD ["/app/transcode.sh"]
