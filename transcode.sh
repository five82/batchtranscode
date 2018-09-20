#!/bin/bash

# ffmpeg batch transcode script
# Author: five82
# https://github.com/five82
# Takes mkv files, analyzes, and batch transcodes automatically based on the following conditions:
#   Number of audio tracks
#   Number of channels in audio tracks. Set bitrate accordingly.
#   Determines crf based of width of video - SD, HD, or 4K
#   Is there a forced subtitle track? If so, set it to forced.

# LIMITATIONS:
# Limit of one subtitle track for input. Will encode as forced.
# Subtitles will be stretched if the video is cropped.
# Sources larger than 1080p must be HDR

# Input and output directories:
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

fun_videoinfo () {
  echo "Video info:"
  echo "input=$input"
  echo "inputfilename=$inputfilename"
  echo "bit depth=${bitdepth}"
  echo "cropblackbars=${cropblackbars}"
  echo "encoder binary=$encoderbinary"
  echo "video crop=$vidcrop"
  echo "mapargs=${mapargs[@]}"
  echo "encoder library=${encoderlib}"
  echo "pixel format=$pixformat"
  echo "preset=${preset}"
  echo "encoderparams=${encoderparams}"
  echo "audsubargs=${audsubargs[@]}"
  echo "tracks=$tracks"
  echo "atracks=$atracks"
  echo "forced=$forced"
  echo "channels=$channels"
  echo "width=$width"
  echo "crf=$crf"
  echo "output=${output}"
}

# Transcoding function
fun_transcode () {

  # Analyze input video
  tracks=$(/app/ffprobe -v error -show_entries format=nb_streams -of default=noprint_wrappers=1:nokey=1:noprint_wrappers=1 "${input}")
  forced=$(/app/ffprobe -v error -show_entries stream=index -select_streams s -of default=noprint_wrappers=1:nokey=1:noprint_wrappers=1 "${input}")
  channels=$(/app/ffprobe -v error -select_streams a:0 -show_entries stream=channels -of default=nokey=1:noprint_wrappers=1 "${input}")
  sourcevidbitdepth=$(mediainfo --Inform="Video;%BitDepth%" "${input}")
  eval $(/app/ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=width "${input}")
  width=${streams_stream_0_width}

  # Select ffmpeg binary for crop detection
  if [ ${cropblackbars} == "true" ]; then
    if [ ${sourcevidbitdepth} == 8 ]; then
      cdencoderbinary="ffmpeg"
    elif [ ${sourcevidbitdepth} == 10 ]; then
      cdencoderbinary="ffmpeg-10bit"
    else
      echo "ERROR: Invalid bit depth of ${sourcevidbitdepth} detected in source. Valid values are 8 or 10. Aborting."
      exit
    fi
  fi

  # Crop black bars
  if [ ${cropblackbars} == "true" ] && (( ${width} <= 1920 )); then
    vidcrop=$(/app/${cdencoderbinary} -ss "${cropscanstart}" -i "${input}" -f matroska -t "${cropscanlength}" -an -vf cropdetect=24:16:0 -y -crf 51 -preset ultrafast /dev/null 2>&1 | grep -o crop=.* | sort -bh | uniq -c | sort -bh | tail -n1 | grep -o crop=.*)
  # Adjust black levels in cropdetect for uhd/hdr
  elif [ ${cropblackbars} == "true" ]; then
    vidcrop=$(/app/${cdencoderbinary} -ss "${cropscanstart}" -i "${input}" -f matroska -t "${cropscanlength}" -an -vf cropdetect=150:16:0 -y -crf 51 -preset ultrafast /dev/null 2>&1 | grep -o crop=.* | sort -bh | uniq -c | sort -bh | tail -n1 | grep -o crop=.*)
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

  # Select ffmpeg encoder based on bitdepth
  if [ ${bitdepth} == 8 ]; then
    encoderbinary="ffmpeg"
    pixformat="yuv420p"
  elif [ ${bitdepth} == 10 ]; then
    encoderbinary="ffmpeg-10bit"
    pixformat="yuv420p10le"
  else
    echo "ERROR: Invalid bit depth of ${bitdepth} specified. Valid values are 8 or 10. Aborting."
    exit
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

  # Set bitrate for audio tracks based on the number of channels
  if [ ${channels} == 2 ]; then
    abitrate=${stereobitrate}
  elif [ ${channels} == 6 ]; then
    abitrate=${surrfiveonebitrate}
  elif [ ${channels} == 8 ]; then
    abitrate=${surrsevenonebitrate}
  else
    echo "ERROR: Invalid channel number ${channels} in first audio track of ${inputfilename}. Aborting."
    exit
  fi

  # Encode
  fun_slackpost "Starting encode: $inputfilename" "INFO"
  i=0
  mapargs=()
  while [ $i -lt $tracks ]; do
    mapargs+=(-map "0:$i")
    let i=i+1
  done
  j=0
  audsubargs=()
  while [ $j -lt $atracks ]; do
    audsubargs+=(-c:a:$j ${audioencoder} -b:a:$j ${abitrate})
    let j=j+1
  done
  if [ ${forced} ]; then
    audsubargs+=(-c:s:0 copy -disposition:s:0 +default+forced)
  fi
  fun_videoinfo
  # Added channel layouts to ffmpeg commands to work around
  # the following ffmpeg libopus defect:
  # https://trac.ffmpeg.org/ticket/5718
  if (( ${width} > 1920 )); then
    # Uncomment to debug
    # FFREPORT=file=/output/ffreport.log \
    /app/${encoderbinary} \
      -i ${input} \
      -vf ${vidcrop} \
      ${mapargs[@]} \
      -af aformat=channel_layouts="7.1|5.1|stereo" \
      -c:v ${encoderlib} \
      -tag:v hvc1 \
      -preset ${preset} \
      -crf ${crf} \
      -pix_fmt ${pixformat} \
      ${encoderparams} "colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc" \
      ${audsubargs[@]} \
      ${output}
  else
    # Uncomment to debug
    # FFREPORT=file=/output/ffreport.log \
    /app/${encoderbinary} \
      -i ${input} \
      -vf ${vidcrop} \
      ${mapargs[@]} \
      -af aformat=channel_layouts="7.1|5.1|stereo" \
      -c:v ${encoderlib} \
      -preset ${preset} \
      -pix_fmt ${pixformat} \
      ${encoderparams} \
      crf=${crf} \
      ${audsubargs[@]} \
      ${output}
  fi
  fun_slackpost "Finished encode: $inputfilename" "INFO"Z
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
