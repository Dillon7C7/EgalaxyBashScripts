#!/bin/sh

if [ "$#" -ne 3 ] ; then
  echo "Usage: $0  Source_Folder  file_name resolution" >&2
  echo "Ex: $0 today  BTL-HannaOrio-60sec.mov   1080" >&2
  echo "Ex: $0 friday  BTL-HannaOrio-60sec.mov   720" >&2
  exit 1
fi

# ./gsk_encode.sh BTL-HannaOrio-60sec.mov ; ./gWM.sh BTL-HannaOrio-60sec.mov ;./g1080_enc.sh BTL-HannaOrio-60sec.mov
source_dir=$1
filename=$2
resolution=$3


cp  ${source_dir}/${filename}  ./${filename}

./gsk_encode.sh ${filename} ; 
./gWM.sh ${filename}  ;
./g${resolution}_enc.sh ${filename}  


