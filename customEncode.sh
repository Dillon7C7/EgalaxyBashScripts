#!/bin/sh

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  printf "%s\\n" "Usage: $0  Source_Folder/file_name resolution [ph]">&2
  printf "%s\\n" "Ex: $0 today/BTL-HannaOrio-60sec.mov 1080" >&2
  printf "%s\\n" "Ex: $0 friday/BTL-HannaOrio-60sec.mov 720 ph" >&2
  exit 1
fi

source_dir="${1%/*}"
filename="${1##*/}"
resolution=$2
ph="$3"

cp "${source_dir}/${filename}" ./"${filename}"

./gsk_encode.sh "${filename}"

# if $3 was not given, or it is not a case sensitive match of "ph", add WM
if [ -z "${ph:+x}" ] || [ $(printf "%s" "$ph" | tr '[:upper:]' '[:lower:]') != ph ]; then
	./gWM.sh "${filename}"
fi
./g${resolution}_enc.sh "${filename}"
