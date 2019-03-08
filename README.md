## batchtranscode Docker image

Available on Docker Hub at https://hub.docker.com/r/five82/batchtranscode/

```docker pull five82/batchtranscode```

Takes video files, analyzes, and batch transcodes automatically using FFmpeg based on the following conditions:
  - Number of audio tracks
  - Number of channels in audio tracks. Set bitrate accordingly.
  - Number of subtitle tracks
  - Determines crf based on width of video - SD, HD, or 4K

All output files will be MKV. Use FFmpeg or other tools to remux if you need a different video container.
The script does support transcoding UHD and HDR videos.

### Description

*batchtranscode is a bash script inside a Docker container that uses FFmpeg to transcode videos. The intention is to simplify your workflow when transcoding multiple videos at once. Drop your videos into a directory and start the container. The script will analyze each video, choose the appropriate encoding parameters, and transcode.*

### Usage

Create input, intermediate, and output directories. Add all video files that you want to encode into your input directory. Start the docker container with the command below and it will sequentially encode each video in the directory. The container will terminate when complete.

    docker run --rm \
    --name batchtranscode \
    -v <path/to/input/dir>:/input \
    -v <path/to/intermediate/dir>:/intermediate \
    -v <path/to/output/dir>:/output \
    five82/batchtranscode

You can also put nested directories containing files into your input directory and batchtranscode will recreate the directory and file structure under the output directory.

### Notes

The script will crop black bars by default. To disable cropping, see the ```cropblackbars``` optional parameter below.

Mapping the intermediate directory is only required if you are transcoding non MKV input files. Batchtranscode will copy and remux the file into an MKV container before transcoding. You will need enough free disk space in your intermediate directory for your largest non MKV input file.

### Optional parameters

*The defaults below were selected because they are optimal for my own encodes. Set the encoder to "x264", bitdepth to "8", and audioencoder to "aac" to ensure maximum compatibility with most devices. (Please note: HDR10 videos require the x265 encoder and a bitdepth of 10.)*

* ```-e encoder="value"```  Specifies the encoder for the video track. Options are ```"x264"``` and ```"x265"```. The default value is ```"x265"```.
* ```-e bitdepth="value"```  Specifies the bitdepth of the encoded video. Options are ```"8"``` and ```"10"```. The default value is ```"10"```.
* ```-e audioencoder="value"```  Specifies the encoder for all audio tracks. Options are ```"aac"``` and ```"libopus"```. The default value is ```"libopus"```. Other FFmpeg supported encoders may work but have not been tested.
* ```-e cropblackbars="value"```  Automatically crops black bars in the encoded video. Options are ```"true"``` to enable and ```"false"``` to disable. The default value is ```"true"```.
* ```-e stereobitrate="value"```  Specifies the bitrate for stereo audio tracks. The default value is ```"128k"```.
* ```-e surrfiveonebitrate="value"```  Specifies the bitrate for 5.1 channel audio tracks. The default value is ```"384k"```.
* ```-e surrsevenonebitrate="value"```  Specifies the bitrate for 7.1 channel audio tracks. The default value is ```"512k```".
* ```-e slackurl="value"```  Set the value of this parameter to your Slack webhook URL if you want Slack notifications when video encodes start and complete.

### FFmpeg optional parameters

* ```-e uhdcrf="value"```  Specifies the crf for videos tracks above a width of 1920 pixels. The default value is ```"20"```.
* ```-e hdcrf="value"```  Specifies the crf for videos tracks with a width between 1250 and 1920 pixels. The default value is ```"21"```.
* ```-e sdcrf="value"```  Specifies the crf for videos tracks below a width of 1250. The default value is ```"20"```.
* ```-e preset="value"``` Specifies the preset for the x264 and x265 encoders. The default value is ```"medium"```. See the [x264 Preset Reference](http://dev.beandog.org/x264_preset_reference.html) for options.
