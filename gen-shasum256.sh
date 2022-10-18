#!/bin/zsh

shasum -a 256 ./**/* > shasum256.txt

cd ./analysis
shasum -a 256 ./**/* > shasum256.txt

cd ../bu_statistics
shasum -a 256 ./**/* > shasum256.txt

cd ../tse_public_data
shasum -a 256 ./**/* > shasum256.txt
