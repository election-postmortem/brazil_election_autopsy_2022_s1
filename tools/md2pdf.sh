#!/bin/bash


MD2HTML_PATH="md2html.sh"

if [ -e "./$MD2HTML_PATH" ]
then
  MD2HTML_PATH="./$MD2HTML_PATH"
elif [ -e "./tools/$MD2HTML_PATH" ]
then
  MD2HTML_PATH="./tools/$MD2HTML_PATH"
elif [ -e "../tools/$MD2HTML_PATH" ]
then
  MD2HTML_PATH="../tools/$MD2HTML_PATH"
elif [ -e "../../tools/$MD2HTML_PATH" ]
then
  MD2HTML_PATH="../../tools/$MD2HTML_PATH"
fi

if [ ! -e "$MD2HTML_PATH" ]; then
  echo "** CAN'T FIND 'md2html': $MD2HTML_PATH"
  exit 1
fi

echo "-- MD2HTML_PATH: $MD2HTML_PATH";

MD_FILE=$1
MD_OUTPUT_FILE=$2

MD_OUTPUT_FILE="${MD_OUTPUT_FILE%.*}"

MD_OUTPUT_FILE_HTML="$MD_OUTPUT_FILE.html"
MD_OUTPUT_FILE_PDF="$MD_OUTPUT_FILE.pdf"

echo "-- MD_FILE: $MD_FILE"
echo "-- MD_OUTPUT_FILE_HTML: $MD_OUTPUT_FILE_HTML"
echo "-- MD_OUTPUT_FILE_HTML: $MD_OUTPUT_FILE_PDF"

$MD2HTML_PATH "$MD_FILE" dark > "$MD_OUTPUT_FILE_HTML"
wkhtmltopdf --outline --enable-local-file-access --print-media-type --no-background --margin-top 12mm --margin-bottom 19mm --footer-line --footer-left "[title]" --footer-right "[page]/[toPage]" --footer-spacing 8 "$MD_OUTPUT_FILE_HTML" "$MD_OUTPUT_FILE_PDF"
