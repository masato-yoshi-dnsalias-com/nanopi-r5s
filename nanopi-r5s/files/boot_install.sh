#!/bin/bash
set -e
MMC_IMAGE=xxxxxx.img.xz

if [ "${1}" = "" ]; then
  echo "usage : $(basename) target"
  exit 0
fi

target_dev="${1}"
target=/tmp/target

if [ -f /${MMC_IMAGE} -a -b ${target_dev} ]; then
  xzcat -v /${MMC_IMAGE} > ${target_dev} 2> /dev/console && sync

  # resize rootfs & change uuid
  target_part=${target_dev}p1
  target_partnum="$(echo "${target_part}" | grep -Eo '[[:digit:]]*$')"
  uuid="$(cat /proc/sys/kernel/random/uuid)"
  echo "write" | sfdisk -f "${target_dev}"
  echo "start=32768, size=" | sfdisk -f "${target_dev}"
  echo "uuid=${uuid}" | sfdisk -f -N "${target_partnum}" "${target_dev}"

  # target folder create & mount
  mkdir -p ${target}
  mount ${target_part} ${target}

  # resize rootfs
  resize2fs "$(findmnt -no source ${target})"
  rm -f "${target}/etc/rc.local"

  # change rootfs uuid
  uuid="$(cat /proc/sys/kernel/random/uuid)"
  echo "changing rootfs uuid: ${uuid}"
  tune2fs -U "${uuid}" "${target_part}"
  chroot ${target} sed -i "s|$(chroot ${target} findmnt -fsno source '/')|UUID=${uuid}|" '/etc/fstab'
  chroot ${target} /boot/mk_uboot_menu

  # machine initialize
  chroot ${target} rm -f /etc/machine-id
  chroot ${target} dbus-uuidgen --ensure=/etc/machine-id
  chroot ${target} dpkg-reconfigure openssh-server
  chroot ${target} systemctl enable ssh.service

  # generate random mac address
  macd=$(xxd -s250 -l6 -p /dev/urandom)

  cat <<-EOF > ${target}/etc/systemd/network/10-name-lan1.link
	[Match]
	Path=platform-3c0000000.pcie-pci-0000:01:00.0
	[Link]
	Name=lan1
	MACAddress=$(printf '%012x' $((0x$macd & 0xfefffffffffc | 0x200000000000)) | sed 's/../&:/g;s/:$//')
	EOF

  cat <<-EOF > ${target}/etc/systemd/network/10-name-lan2.link
	[Match]
	Path=platform-3c0400000.pcie-pci-0001:01:00.0
	[Link]
	Name=lan2
	MACAddress=$(printf '%012x' $((0x$macd & 0xfefffffffffc | 0x200000000001)) | sed 's/../&:/g;s/:$//')
	EOF

  cat <<-EOF > ${target}/etc/systemd/network/10-name-wan0.link
	[Match]
	Path=platform-fe2a0000.ethernet
	[Link]
	Name=wan0
	MACAddress=$(printf '%012x' $((0x$macd & 0xfefffffffffc | 0x200000000002)) | sed 's/../&:/g;s/:$//')
	EOF

  # setup for expand fs
  sync; sync
  umount ${target}
fi
