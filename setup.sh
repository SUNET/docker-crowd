#!/bin/bash

set -e
set -x

export DEBIAN_FRONTEND noninteractive

# Update the image and install the needed tools
apt-get update && \
    apt-get -y dist-upgrade && \
    apt-get install -y \
        ssl-cert\
    && apt-get -y autoremove \
    && apt-get autoclean

# Do some more cleanup to save space
rm -rf /var/lib/apt/lists/*
