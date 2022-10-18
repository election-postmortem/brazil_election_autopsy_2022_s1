#!/bin/sh

if [ "$1" = "" ]; then
  echo "USAGE:"
  echo ""
  echo "  DIRECTORY:"
  echo "  ./run-bu-dump.sh /bu-files/sp/61000"
  echo ""
  echo "  FILE:"
  echo "  ./run-bu-dump.sh /bu-files/sp/61000/sp-61000-0330-0017.bu"
  echo ""

  exit 0
fi

if [ -d "$1" ]; then
  DIR=$1;
  echo "PROCESSING DIRECTORY: $DIR"

  python /bu/python/bu_dump_json.py -a /bu/spec/bu.asn1 -b $DIR

  echo "COMPRESSING: $DIR"
  gzip -3 -fv "$DIR"/*.bu.json

  exit 0
else
  FILE=$1
  FILE_JSON="$FILE.json"
  python /bu/python/bu_dump_json.py -a /bu/spec/bu.asn1 -b $FILE
  gzip -3 -fv "$FILE_JSON"
fi
