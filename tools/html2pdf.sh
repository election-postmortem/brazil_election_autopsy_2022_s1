#!/bin/bash

INPUT_FILE_HTML=$1

OUTPUT_FILE_PDF="${INPUT_FILE_HTML%.*}.pdf"

echo "-- INPUT_FILE_HTML: $INPUT_FILE_HTML"
echo "-- OUTPUT_FILE_PDF: $OUTPUT_FILE_PDF"

wkhtmltopdf --outline --enable-local-file-access --print-media-type --no-background --margin-top 12mm --margin-bottom 19mm --footer-line --footer-left "[title]" --footer-right "[page]/[toPage]" --footer-spacing 8 "$INPUT_FILE_HTML" "$OUTPUT_FILE_PDF"
