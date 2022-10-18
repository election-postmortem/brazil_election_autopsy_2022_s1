#!/bin/bash

TEMPLATE_FILE="md-template-dark.html"

if [ "$2" == "light" ]
then
  TEMPLATE_FILE="md-template-light.html"
fi


if [ -e "./$TEMPLATE_FILE" ]
then
  TEMPLATE_FILE="./$TEMPLATE_FILE"
elif [ -e "./tools/$TEMPLATE_FILE" ]
then
  TEMPLATE_FILE="./tools/$TEMPLATE_FILE"
elif [ -e "../tools/$TEMPLATE_FILE" ]
then
  TEMPLATE_FILE="../tools/$TEMPLATE_FILE"
elif [ -e "../../tools/$TEMPLATE_FILE" ]
then
  TEMPLATE_FILE="../../tools/$TEMPLATE_FILE"
fi

if [ ! -e "$TEMPLATE_FILE" ]; then
  echo "** CAN'T FIND TEMPLATE FILE: $TEMPLATE_FILE"
  exit 1
fi


TEMPLATE_DOC=$(cat "$TEMPLATE_FILE")

MD_FILE=$1

TITLE=$(head -1 "$MD_FILE")
TITLE="${TITLE:2}"

MD_DOC=$(markdown --extension-set GitHubFlavored "$MD_FILE")

echo "$(eval "echo \"$TEMPLATE_DOC\"")"
