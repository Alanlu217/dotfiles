#!/usr/bin/env bash

if [ "$(pidof $1)" == "" ]; then
  echo 0
else
  echo 1
fi
