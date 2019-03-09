#!/bin/bash

# ffmpeg batch transcode script
# Author: five82
# https://github.com/five82
# Takes video files, analyzes, and batch transcodes automatically based on the following conditions:
#   Number of audio tracks
#   Number of channels in audio tracks. Set bitrate accordingly.
#   Number of subtitle tracks
#   Determines crf based on width of video - SD, HD, or 4K or higher resolutions
# Supports transcoding UHD and HDR videos

# LIMITATIONS:
#   Transcoded videos will be MKV
#   Non MKV input files will be copied and remuxed to MKV before being transcoded
#   You must have enough free disk space in your intermediate directory for your largest non MKV input file

# Encoder binary
encoderbinary="ffmpeg"

# Input and output directories:
inputdir=/input
intermediatedir=/intermediate
outputdir=/output

fun_timestamp () {
  date +"%T"
}

fun_slackpost () {
  if ! [ -z "$slackurl" ]; then
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
    curl --fail --silent --show-error -X POST --data "payload={\"text\": \"${slackicon} $(fun_timestamp) UTC - ${slackmsg}\"}" ${slackurl} > /dev/null

  fi
}

fun_videoinfo () {
  echo "Video info:"
  echo "input=${input}"
  echo "output=${output}"
  echo "input file name=${workingfilename}"
  echo "working directory"=${workingdir}
  echo "intermediate directory"=${intermediatedir}
  echo "output directory"=${outputdir}
  echo "bit depth=${bitdepth}"
  echo "crop black bars=${cropblackbars}"
  echo "encoder binary=${encoderbinary}"
  echo "video crop=${vidcrop}"
  echo "vidcroparray0=${vidcroparray[0]}"
  echo "vidcroparray1=${vidcroparray[1]}"
  echo "vidcroparray2=${vidcroparray[2]}"
  echo "vidcroparray3=${vidcroparray[3]}"
  echo "vidcroparray4=${vidcroparray[4]}"
  echo "mapargs=${mapargs[@]}"
  echo "encoder library=${encoderlib}"
  echo "pixel format=$pixformat"
  echo "ffmpeg preset=${preset}"
  echo "encoder params=${encoderparams}"
  echo "audio args=${audioargs[@]}"
  echo "subtitle args=${subtitleargs[@]}"
  echo "tracks=${tracks}"
  echo "audio tracks=${atracks}"
  echo "subtitle tracks=${stracks}"
  echo "source video duration=${sourcevidduration}"
  echo "source color primaries=${sourcecolorprimaries}"
  echo "width=${width}"
  echo "crf=${crf}"
  echo "slack url"=${slackurl}
}

fun_vidcompare () {
  n=0
  for l in {0..4}
  do
    if [ "${vidbasestring}" == "${vidcroparray[$l]}" ]; then
      n=$(( $n+1 ))
    fi
  done
  if [ "${n}" -ge "3" ]; then
    vidcrop=${vidbasestring}
  fi
}

# Transcoding function
fun_transcode () {

  # Analyze input video
  tracks=$(ffprobe -show_entries format=nb_streams -v 0 -of compact=p=0:nk=1 "${input}")
  atracks=$(ffprobe -i "${input}" -v 0 -select_streams a -show_entries stream=index -of compact=p=0:nk=1 | wc -l)
  stracks=$(ffprobe -i "${input}" -v 0 -select_streams s -show_entries stream=index -of compact=p=0:nk=1 | wc -l)
  sourcevidduration=$(ffprobe -i "${input}" -show_format -v quiet | sed -n 's/duration=//p' | xargs printf %.0f)
  sourcecolorprimaries=$(ffprobe -i "${input}" -show_streams -v quiet | sed -n 's/color_primaries=//p' | xargs printf %s)
  eval $(ffprobe -v error -of flat=s=_ -select_streams v:0 -show_entries stream=width "${input}")
  width=${streams_stream_0_width}

  # Crop black bars
  # Scan the video at five different timestamps.
  # If the crop values of the majority match, consider the result valid.
  if [ ${cropblackbars} == "true" ]; then
    echo "INFO: Determining black bar crop values."
    cropscanarray=()
    cropscanarray[0]=$(( ${sourcevidduration}*15/100 ))
    cropscanarray[1]=$(( ${sourcevidduration}*3/10 ))
    cropscanarray[2]=$(( ${sourcevidduration}*45/100 ))
    cropscanarray[3]=$(( ${sourcevidduration}*6/10 ))
    cropscanarray[4]=$(( ${sourcevidduration}*75/100 ))
    vidcroparray=()
    for k in {0..4}
    do
      if [[ ${sourcecolorprimaries} = "bt2020" ]]; then
        vidcroparray[$k]=$(${encoderbinary} -ss "${cropscanarray[$k]}" -i "${input}" -f matroska -t "10" -an -sn -vf zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p,cropdetect=24:16:0 -y -crf 25 -preset ultrafast /dev/null 2>&1 | grep -o crop=.* | sort -b | uniq -c | sort -b | tail -n1 | grep -o crop=.*)
      else
        vidcroparray[$k]=$(${encoderbinary} -ss "${cropscanarray[$k]}" -i "${input}" -f matroska -t "10" -an -sn -vf cropdetect=24:16:0 -y -crf 25 -preset ultrafast /dev/null 2>&1 | grep -o crop=.* | sort -b | uniq -c | sort -b | tail -n1 | grep -o crop=.*)
      fi
    done
    vidbasestring=${vidcroparray[0]}
    fun_vidcompare
    if [[ -z ${vidcrop} ]]; then
      vidbasestring=${vidcroparray[1]}
      fun_vidcompare
    fi
    if [[ -z ${vidcrop} ]]; then
      vidbasestring=${vidcroparray[2]}
      fun_vidcompare
    fi
    if [[ -z ${vidcrop} ]]; then
      echo "ERROR: Crop detection failed for ${input}. Could not find a valid crop value. Skipping transcode job."
      echo "Crop values: ${vidcroparray[@]}"
      fun_slackpost "ERROR: Crop detection failed for ${input}. Could not find a valid crop value. Skipping transcode job." "ERROR"
      return 0
    fi
  else
    # Don't crop
    vidcrop="crop=in_w:in_h"
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
    pixformat="yuv420p"
  elif [ ${bitdepth} == 10 ]; then
    pixformat="yuv420p10le"
  else
    echo "ERROR: Invalid bit depth of ${bitdepth} specified. Valid values are 8 or 10. Aborting."
    fun_slackpost "ERROR: Invalid bit depth of ${bitdepth} specified. Valid values are 8 or 10. Aborting." "ERROR"
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
    fun_slackpost "ERROR: Invalid encoder ${encoder} specified. Set the encoder to x264 or x265. Aborting." "ERROR"
    exit
  fi

  # Encode
  echo "INFO: Starting encode: $workingfilename"
  fun_slackpost "Starting encode: $workingfilename" "INFO"
  i=0
  mapargs=()
  while [ $i -lt $tracks ]; do
    mapargs+=(-map "0:$i")
    let i=i+1
  done
  j=0
  audioargs=()
  while [ $j -lt $atracks ]; do
    channels=$(ffprobe -v error -select_streams a:$j -show_entries stream=channels -of default=nokey=1:noprint_wrappers=1 "${input}")
    # Determine bitrate based on number of channels
    if [ ${channels} == 2 ]; then
      abitrate=${stereobitrate}
    elif [ ${channels} == 6 ]; then
      abitrate=${surrfiveonebitrate}
    elif [ ${channels} == 8 ]; then
      abitrate=${surrsevenonebitrate}
    else
      echo "ERROR: Invalid channel number ${channels} in audio track of ${workingfilename}. Skipping job."
      fun_slackpost "ERROR: Invalid channel number ${channels} in audio track of ${workingfilename}. Skipping job." "ERROR"
      return 0
    fi
    audioargs+=(-c:a:$j ${audioencoder} -b:a:$j ${abitrate})
    let j=j+1
  done
  k=0
  subtitleargs=()
  while [ $k -lt $stracks ]; do
    subtitleargs+=(-c:s:$k copy)
    let k=k+1
  done
  fun_videoinfo
  # Added channel layouts to ffmpeg commands to work around
  # the following ffmpeg libopus defect:
  # https://trac.ffmpeg.org/ticket/5718
  # If the source video is HDR, use the following encoding parameters:
  if [ ${sourcecolorprimaries} == "bt2020" ]; then
    # Uncomment to debug
    # FFREPORT=file=/output/ffreport-$(date -d "today" +"%Y%m%d%H%M").log \
    ${encoderbinary} \
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
      ${audioargs[@]} \
      ${subtitleargs[@]} \
      ${output}
  else
    # Uncomment to debug
    # FFREPORT=file=/output/ffreport-$(date -d "today" +"%Y%m%d%H%M").log \
    ${encoderbinary} \
      -i ${input} \
      -vf ${vidcrop} \
      ${mapargs[@]} \
      -af aformat=channel_layouts="7.1|5.1|stereo" \
      -c:v ${encoderlib} \
      -preset ${preset} \
      -pix_fmt ${pixformat} \
      ${encoderparams} \
      crf=${crf} \
      ${audioargs[@]} \
      ${subtitleargs[@]} \
      ${output}
  fi
  echo "INFO: Finished encode: $workingfilename"
  fun_slackpost "Finished encode: $workingfilename" "INFO"
}

# Transcode each file in the input directory tree
echo "INFO: Starting transcode queue jobs."
fun_slackpost "Starting transcode queue jobs." "INFO"
rsync -a -f"+ */" -f"- *" "${inputdir}/" "${outputdir}/"
SAVEIFS=$IFS
IFS=$(echo -en "\n\b")
mkfifo pipefile
find ${inputdir} -type f > pipefile &
while read input <&3; do
  workingdir="${input%/*}"
  workingfilename=$(basename "${input}")
  outputdir=$(echo ${workingdir} | sed -e "s/\input/output/g")
  output="${outputdir}/${workingfilename}"
  # If the input is not an MKV file, copy and remux it to MKV.
  if [ ! ${input: -4} == ".mkv" ]; then
    echo "INFO: Remuxing ${workingfilename} into an MKV container."
    ${encoderbinary}  \
      -i ${input}  \
      -c copy \
      "${intermediatedir}/${workingfilename%.*}.mkv"
    input="${intermediatedir}/${workingfilename%.*}.mkv"
    output="${outputdir}/${workingfilename%.*}.mkv"
    workingdir=${intermediatedir}
  fi
  if [ -f ${output} ]; then
    echo "WARNING: ${output} already exists. Skipping transcode job."
    fun_slackpost "WARNING: ${output} already exists. Skipping transcode job." "WARNING"
    rm -rf ${intermediatedir}/*
  else
    fun_transcode
    rm -rf ${intermediatedir}/*
  fi
done 3< pipefile
rm pipefile
echo "INFO: All jobs in transcode queue are finished."
fun_slackpost "All jobs in transcode queue are finished." "INFO"
IFS=$SAVEIFS
