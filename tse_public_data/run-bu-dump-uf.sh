#!/bin/sh

UF=$1
UF_DIR="bu-files/$UF"

echo "UF DIRECTORY: $UF_DIR"

for CITY_DIR in "$UF_DIR"/*
do
  echo "-----------------------------------------------------"

  NEED=0

  for FILE in "$CITY_DIR"/*
  do
    if [ "${FILE##*.}" = "bu" ]
    then
      FILE_BU="${FILE%.*}.bu"
      echo "=== $FILE_BU"
      if [ ! -f "${FILE_BU}.json" ] && [ ! -f "${FILE_BU}.json.gz" ]; then
        echo "NEED: $FILE_BU"
        NEED=1
        break
      fi
    fi
  done

  if [ "$NEED" = "1" ]; then
    echo "DIR: /$CITY_DIR"
    ./run-bu-dump-json.sh "/$CITY_DIR"
  fi

done

exit 0
