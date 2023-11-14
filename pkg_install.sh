#!/bin/bash
set -e

  pkg="bc bison curl debootstrap device-tree-compiler fdisk flex gcc libssl-dev make mmdebstrap"
  pkg="${pkg} python3-dev python3-pyelftools python3-setuptools swig vim wget"

  DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y ${pkg}
