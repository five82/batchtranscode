#!/bin/bash

# ffmpeg batch transcode script
# Author: five82
# https://github.com/five82
# Takes mkv files, analyzes, and batch transcodes automatically based on the following conditions:
#   number of audio tracks
#   number of channels in the first audio track. set bitrate accordingly.
#   determines crf based of width of video - sd, hd, or 4k
#   is there a forced subtitle track? if so, set it to forced.

# LIMITATIONS:
# limit of five audio tracks for input video
# limit of one forced subtitle track for input video
# stereo only output for second, third, fourth and fifth audio tracks (intended for commentary tracks)


# INPUT AND OUTPUT DIRECTORIES:
inputdir=/input
outputdir=/output

fun_slackpost () {
  slackmsg="$1"
  case "$2" in
    INFO)
      slackicon=':slack:'
      ;;
    WARNING)
      slackicon=':warning:'
      ;;
    ERROR)
      slackicon=':bangbang:'
      ;;
    *)
      slackicon=':slack:'
      ;;
  esac
  curl -X POST --data "payload={\"text\": \"${slackicon} ${slackmsg}\"}" ${slackurl}
}

# Transcoding function
fun_transcode () {

  # Analyze input video
  tracks=$(/app/ffprobe -v error -show_entries format=nb_streams -of default=noprint_wrappers=1:nokey=1:noprint_wrappers=1 "${input}")
  forced=$(/app/ffprobe -v error -show_entries stream=index -select_streams s -of default=noprint_wrappers=1:nokey=1:noprint_wrappers=1 "${input}")
  channels=$(/app/ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=nokey=1:noprint_wrappers=1 "${input}")
  inputvcodec=$(/app/ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=nokey=1:noprint_wrappers=1 "${input}")
  eval $(/app/ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=width "${input}")
  width=${streams_stream_0_width}

  # Crop black bars
  if [ ${cropblackbars} == "true" ] && (( ${width} <= 1920 )); then
    vidcrop=$(/app/ffmpeg -ss "${cropscanstart}" -i "${input}" -f matroska -t "${cropscanlength}" -an -vf cropdetect=24:16:0 -y -crf 51 -preset ultrafast /dev/null 2>&1 | grep -o crop=.* | sort -bh | uniq -c | sort -bh | tail -n1 | grep -o crop=.*)
  # Adjust black levels in cropdetect for uhd/hdr
  elif [ ${cropblackbars} == "true" ]; then
    vidcrop=$(/app/ffmpeg -ss "${cropscanstart}" -i "${input}" -f matroska -t "${cropscanlength}" -an -vf cropdetect=150:16:0 -y -crf 51 -preset ultrafast /dev/null 2>&1 | grep -o crop=.* | sort -bh | uniq -c | sort -bh | tail -n1 | grep -o crop=.*)
  else
    # Don't crop
    vidcrop="crop=in_w:in_h"
  fi

  # Determine output file name
  inputfilename=$(basename "${input}")
  output="${outputdir}/${inputfilename}"

  # Determine number of audio tracks
  if [ ${forced} ]; then
    atracks=$(( $tracks-2 ))
  else
    atracks=$(( $tracks-1 ))
  fi

  # Set crf based on video width
  if (( ${width} < 1250 )); then
    crf=${sdcrf}
  elif (( ${width} <= 1920 )); then
    crf=${hdcrf}
  else
    crf=${uhdcrf}
  fi

  # Set encoder variables
  if [ ${encoder} == "x264" ]; then
    encoderlib="libx264"
    encoderparams="-x264-params"
  elif [ ${encoder} == "x265" ]; then
    encoderlib="libx265"
    encoderparams="-x265-params"
  else
    echo "ERROR: Invalid encoder ${encoder} specified. Set the encoder to x264 or x265. Aborting."
    exit
  fi

  # Set bitrate for first audio track based on the number of channels
  if [ ${channels} == 2 ]; then
    abitrate="128k"
  elif [ ${channels} == 6 ]; then
    abitrate="384k"
  elif [ ${channels} == 8 ]; then
    abitrate="512k"
  else
    echo "ERROR: Invalid channel number ${channels} in first audio track of ${inputfilename}. Aborting."
    exit
  fi

  # Transcode
  if [ ${atracks} == 1 ] && [ !  ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 1 audio track, no subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 1 ] && [ ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 1 audio track, subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:s:0 copy -disposition:s:0 +default+forced \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 2 ] && [ ! ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 2 audio tracks, no subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 2 ] && [ ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 2 audio tracks, subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:s:0 copy -disposition:s:0 +default+forced \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 3 ] && [ ! ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 3 audio tracks, no subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:a:2 ${audioencoder} -b:a:2 128k \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 3 ] && [ ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 3 audio tracks, subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 -map 0:4 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:a:2 ${audioencoder} -b:a:2 128k \
      -c:s:0 copy -disposition:s:0 +default+forced \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 4 ] && [ ! ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 4 audio tracks, no subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 -map 0:4 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:a:2 ${audioencoder} -b:a:2 128k \
      -c:a:3 ${audioencoder} -b:a:3 128k \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 4 ] && [ ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 4 audio tracks, subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 -map 0:4 -map 0:5 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:a:2 ${audioencoder} -b:a:2 128k \
      -c:a:3 ${audioencoder} -b:a:3 128k \
      -c:s:0 copy -disposition:s:0 +default+forced \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 5 ] && [ ! ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 5 audio tracks, no subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 -map 0:4 -map 0:5 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:a:2 ${audioencoder} -b:a:2 128k \
      -c:a:3 ${audioencoder} -b:a:3 128k \
      -c:a:4 ${audioencoder} -b:a:4 128k \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  elif [ ${atracks} == 5 ] && [ ${forced} ]; then
    echo "inputfilename=$inputfilename"
    echo "atracks=$atracks"
    echo "forced=$forced"
    echo "You have selected 5 audio tracks, subtitles."
    fun_slackpost "Starting encode: $inputfilename" "INFO"
    /app/ffmpeg \
      -i ${input} \
      -vf ${vidcrop} \
      -map 0:0 -map 0:1 -map 0:2 -map 0:3 -map 0:4 -map 0:5 -map 0:6 \
      -c:v ${encoderlib} -preset ${preset} ${encoderparams} crf=${crf} \
      -c:a:0 ${audioencoder} -b:a:0 ${abitrate} \
      -c:a:1 ${audioencoder} -b:a:1 128k \
      -c:a:2 ${audioencoder} -b:a:2 128k \
      -c:a:3 ${audioencoder} -b:a:3 128k \
      -c:a:4 ${audioencoder} -b:a:4 128k \
      -c:s:0 copy -disposition:s:0 +default+forced \
      ${output}
    fun_slackpost "Finished encode: $inputfilename" "INFO"
  else
    echo "ERROR: Invalid encoding parameters Aborting."
    echo "inputfilename=$inputfilename"
    echo "output=$output"
    echo "tracks=$tracks"
    echo "atracks=$atracks"
    echo "abitrate=$abitrate"
    echo "forced=$forced"
    echo "channels=$channels"
    echo "width=$width"
    echo "crf=$crf"
    exit
  fi  

  # Add HDR metadata to the MKV container header for UHD files
  # FFmpeg doesn't copy the metadata yet when encoding
  if (( ${width} > 1920 )); then
    mkvpropedit --edit track:1 -s colour-primaries=9 -s colour-transfer-characteristics=16 -s colour-matrix-coefficients=9 ${output}
  fi
}


# Transcode each file in the input directory
count=0
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")
for input in ${inputdir}/*.mkv; do
  count=$(( $count+1 ))
  echo "INFO: Transcode $count. File: ${input}."
  fun_transcode
done
fun_slackpost "Job complete." "INFO"
IFS=$SAVEIFS
