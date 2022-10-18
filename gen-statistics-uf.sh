#!/bin/bash

UF=$1

cd bu_statistics/

dart run bin/bu_statistics.dart ../tse_public_data/bu-files/bus-$UF.comp ../analysis/$UF commadecimal
