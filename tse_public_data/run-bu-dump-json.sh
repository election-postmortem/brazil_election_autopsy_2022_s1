#!/bin/sh

docker run --rm -v $(pwd)/bu-files:/bu-files bu-docker $@
