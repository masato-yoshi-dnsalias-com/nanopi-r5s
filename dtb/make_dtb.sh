#!/bin/bash

set -e

  cd "$(dirname "$(realpath "${0}")")"

  linux_src='https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.5.tar.xz'
  linux_file="$(basename "${linux_src}")"
  linux_ver="$(echo "${linux_file}" | sed -nE 's/linux-(.*)\.tar\..z/\1/p')"

  [ -f "${linux_file}" ] || curl -O ${linux_src}

  rkpath="linux-${linux_ver}/arch/arm64/boot/dts/rockchip"
  if ! [ -d "linux-${linux_ver}" ]; then
    tar xavf "${linux_file}" "linux-${linux_ver}/include/dt-bindings" "linux-${linux_ver}/include/uapi" "${rkpath}"

    patches="$(find patches -maxdepth 1 -name '*.patch' 2>/dev/null | sort)"
    for patch in ${patches}; do
      patch -p1 -d "linux-${linux_ver}" -i "../${patch}"
    done
  fi

  # build
  dts='rk3568-nanopi-r5c rk3568-nanopi-r5s'
  fldtc='-Wno-interrupt_provider -Wno-unique_unit_address -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size -Wno-alias_paths -Wno-graph_child_address -Wno-simple_bus_reg'
  for dt in ${dts}; do
    gcc -I "linux-${linux_ver}/include" -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o "${dt}-top.dts" "${rkpath}/${dt}.dts"
    dtc -I dts -O dtb -b 0 ${fldtc} -o "${dt}.dtb" "${dt}-top.dts"
    echo -e "\ndevice tree ready: ${dt}.dtb\n"
  done
