#!/usr/bin/env bash

SCRIPT=$(realpath "$0")
BASEDIR=$(dirname "$SCRIPT")

CONF=$1
CONF_BASE=$(basename "$CONF")

rm -rf ~/.config/$CONF
ln -s $BASEDIR/$CONF ~/.config/$CONF_BASE

