#!/bin/bash
set -e

  cd "$(dirname "$(realpath "${0}")")"

  utag='v2023.10'
  atf_file='../rkbin/bin/rk35/rk3568_bl31_v1.43.elf'
  tpl_file='../rkbin/bin/rk35/rk3568_ddr_1560MHz_v1.18.bin'

  if [ ! -d u-boot ]; then
    git clone https://github.com/u-boot/u-boot.git -b ${utag}
  fi

  if [ ! -d rkbin ]; then
    git clone https://github.com/rockchip-linux/rkbin
  fi

  rm -f idbloader*.img u-boot*.itb

  models='r5s'
  make -C u-boot distclean

  for model in ${models}; do
    echo -e "\nconfiguring nanopi-${model}"
    make -C u-boot "nanopi-${model}-rk3568_defconfig"

    echo -e "\nbuilding nanopi-${model}"
    make -C u-boot -j$(nproc) BL31="${atf_file}" ROCKCHIP_TPL="${tpl_file}"
    cp 'u-boot/idbloader.img' "idbloader-${model}.img"
    cp 'u-boot/u-boot.itb' "u-boot-${model}.itb"
  done
  for model in ${models}; do
    echo "copy nanopi ${model} images to media:"
    echo "  sudo dd bs=4K seek=8 if=idbloader-${model}.img of=/dev/sdX conv=notrunc"
    echo "  sudo dd bs=4K seek=2048 if=u-boot-${model}.itb of=/dev/sdX conv=notrunc,fsync"
    echo
  done
