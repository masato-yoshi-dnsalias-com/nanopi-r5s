#!/bin/bash
set +o noclobber

image_size="4g"
image_file="mmc_${image_size}.img"
ubuntu_dist="jammy"
hostname="nanopi-r5s"
user="ubuntu"
password="ubuntu"

mountpt='rootfs'

dtb_file=rk3568-nanopi-r5s.dtb
uboot_spl_file=idbloader-r5s.img
uboot_itb_file=u-boot-r5s.itb

uboot_spl=cache.${ubuntu_dist}/${uboot_spl_file}
uboot_itb=cache.${ubuntu_dist}/${uboot_itb_file}
dtb=cache.${ubuntu_dist}/${dtb_file}

on_exit() {

  if mountpoint -q "${mountpt}"; then
    mountpoint -q "${mountpt}/var/cache" && umount "${mountpt}/var/cache"
    mountpoint -q "${mountpt}/var/lib/apt/lists" && umount "${mountpt}/var/lib/apt/lists"

    read -p "${mountpt} is still mounted, unmount? <Y/n> " yn
    if [ -z "${yn}" -o "${yn}" = 'y' -o "${yn}" = 'Y' ]; then
      echo "unmounting ${mountpt}"
      umount "${mountpt}"
      sync
      rm -rf "${mountpt}"
    fi
  fi
  exit 9

}

trap on_exit EXIT INT QUIT ABRT TERM

  if [ 0 -ne $(id -u) ]; then
    echo 'this script must be run as root'
    echo "   run: sudo sh $(basename "${0}")\n"
    exit 9
  fi

  cd "$(dirname "$(realpath "${0}")")"

  if [ ! -d cache.${ubuntu_dist} ]; then
    mkdir -p cache.${ubuntu_dist}
    # copy dtb
    cp -p ../dtb/${dtb_file} ${dtb}
    # copy uboot file
    cp -p ../uboot/${uboot_spl_file} ${uboot_spl}
    cp -p ../uboot/${uboot_itb_file} ${uboot_itb}
  fi

  [ "${1}" = "nocomp" ] && compress="${1}"

  # setup media
  if [ ! -b "$media" ]; then
    echo "creating image file"
    rm -f "${image_file}"*
    size="$(echo "${image_file}" | sed -rn 's/.*mmc_([[:digit:]]+[m|g])\.img$/\1/p')"
    truncate -s "${size}" "${image_file}"
  fi

  # partition with gpt
  echo "partitioning media"
  cat <<-EOF | sfdisk "${image_file}"
	label: gpt
	unit: sectors
	first-lba: 2048
	part1: start=32768, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=rootfs
	EOF
  sync

  # create ext4 filesystem
  if [ ! -b "${image_file}" ]; then
    lodev="$(losetup -f)"
    partnum="${partnum:-1}"
    losetup -vP "${lodev}" "${image_file}" && sync
    mkfs.ext4 -L rootfs -vO metadata_csum_seed "${lodev}p${partnum}" && sync
    losetup -vd "${lodev}" && sync
  fi

  if [ -d "${mountpt}" ]; then
    mountpoint -q "${mountpt}/var/cache" && umount "${mountpt}/var/cache"
    mountpoint -q "${mountpt}/var/lib/apt/lists" && umount "${mountpt}/var/lib/apt/lists"
    mountpoint -q "${mountpt}" && umount "${mountpt}"
  else
    mkdir -p "${mountpt}"
  fi

  if [ -f "${image_file}" ]; then
    mount -no loop,offset=16M "${image_file}" "${mountpt}"
    success_msg="media ${image_file} partition 1 successfully mounted on ${mountpt}"
  else
    echo "file not found: ${image_file}"
    exit 4
  fi

  if [ ! -d "${mountpt}/lost+found" ]; then
    echo 'failed to mount the image file'
    exit 3
  fi

  echo "${success_msg}"

  echo "configuring files"
  mkdir "${mountpt}/etc"
  echo 'link_in_boot = 1' > "${mountpt}/etc/kernel-img.conf"
  echo 'do_symlinks = 0' >> "${mountpt}/etc/kernel-img.conf"

  # setup fstab
  mdev="$(findmnt -no source "${mountpt}")"
  uuid="$(blkid -o value -s UUID "${mdev}")"
  cat <<-EOF > "${mountpt}/etc/fstab"
	# if editing the device name for the root entry, it is necessary
	# to regenerate the extlinux.conf file by running /boot/mk_extlinux
	
	# <device>                                      <mount> <type>  <options>               <dump> <pass>
	UUID=$uuid      /       ext4    errors=remount-ro       0      1
	EOF

  # setup extlinux boot
  install -Dvm 754 'files/dtb_file_cp' "${mountpt}/etc/kernel/postinst.d/dtb_file_cp"
  install -Dvm 754 'files/dtb_file_rm' "${mountpt}/etc/kernel/postrm.d/dtb_file_rm"
  install -Dvm 754 'files/mk_uboot_menu' "${mountpt}/boot/mk_uboot_menu"
  ln -svf '../../../boot/mk_uboot_menu' "${mountpt}/etc/kernel/postinst.d/update_extlinux"
  ln -svf '../../../boot/mk_uboot_menu' "${mountpt}/etc/kernel/postrm.d/update_extlinux"

  # install device tree
  install -vm 644 "${dtb}" "${mountpt}/boot"

  # install ubuntu linux from deb packages (mmdebstrap)
  echo "installing root filesystem from ubuntu.com"

  echo "installing Kernel Module Load File to /etc/modules"
  install -Dvm 644 'files/modules' "${mountpt}/etc/modules"

  pkgs="bash-completion, bridge-utils, bind9-dnsutils, cockpit, cockpit-networkmanager, cockpit-pcp, cockpit-storaged, conntrack"
  pkgs="${pkgs}, dbus, fdisk, file, gdisk, htop"
  pkgs="${pkgs}, iftop, inetutils-traceroute, initramfs-tools"
  pkgs="${pkgs}, libpam-systemd, libosinfo-bin, linux-image-generic-hwe-22.04, lm-sensors, lshw"
  pkgs="${pkgs}, man-db, nano, net-tools, openvswitch-switch, openssh-server, pciutils, perl"
  pkgs="${pkgs}, systemd-timesyncd, tcpdump, usbutils, vim, wireless-regdb, wpasupplicant xz-utils"
  pkgs="${pkgs}, ${extra_pkgs}"
  cat /etc/apt/sources.list | mmdebstrap --debug --skip=check/empty --components="main restricted universe multiverse" --include "${pkgs}" "${deb_dist}" "${mountpt}" -
  chroot "${mountpt}" dpkg -P flash-kernel

  cat <<-EOF > "${mountpt}/etc/default/locale"
	LANG="C.UTF-8"
	LANGUAGE=
	LC_CTYPE="C.UTF-8"
	LC_NUMERIC="C.UTF-8"
	LC_TIME="C.UTF-8"
	LC_COLLATE="C.UTF-8"
	LC_MONETARY="C.UTF-8"
	LC_MESSAGES="C.UTF-8"
	LC_PAPER="C.UTF-8"
	LC_NAME="C.UTF-8"
	LC_ADDRESS="C.UTF-8"
	LC_TELEPHONE="C.UTF-8"
	LC_MEASUREMENT="C.UTF-8"
	LC_IDENTIFICATION="C.UTF-8"
	LC_ALL=
	EOF

  # wpa supplicant
  rm -rfv "${mountpt}/etc/systemd/system/multi-user.target.wants/wpa_supplicant.service"
  cat <<-EOF > "${mountpt}/etc/wpa_supplicant/wpa_supplicant.conf"
	ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
	update_config=1
	EOF
  cp -v "${mountpt}/usr/share/dhcpcd/hooks/10-wpa_supplicant" "${mountpt}/usr/lib/dhcpcd/dhcpcd-hooks"

  # hostname
  echo "${hostname}" > "${mountpt}/etc/hostname"
  sed -i "s/127.0.0.1\tlocalhost/127.0.0.1\tlocalhost\n127.0.1.1\t${hostname}/" "${mountpt}/etc/hosts"

  echo "creating user account"
  chroot "${mountpt}" /usr/sbin/useradd -m "${user}" -s '/bin/bash'
  chroot "${mountpt}" sh -c "/usr/bin/echo ${user}:${password} | /usr/sbin/chpasswd -c SHA512"
  chroot "${mountpt}" /usr/bin/passwd -e "${user}"
  (umask 377 && echo "${user} ALL=(ALL) NOPASSWD: ALL" > "${mountpt}/etc/sudoers.d/${user}")

  echo "installing rootfs expansion script to /etc/rc.local"
  install -Dvm 754 'files/rc.local' "${mountpt}/etc/rc.local"
  sed -i "s/MMC_IMAGE=xxxxxx.img.xz/MMC_IMAGE=${image_file}.xz/" "${mountpt}/etc/rc.local"

  echo "installing netplan config file to /etc/netplan/01-netcfg.yaml"
  install -Dvm 600 'files/01-netcfg.yaml' "${mountpt}/etc/netplan/01-netcfg.yaml"

  # enable ssh root login
  chroot "${mountpt}" sed -i -e 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

  # cockpit.socket enable
  chroot "${mountpt}" systemctl enable cockpit.socket

  # systemd-networkd-wait-online.servcie disable
  chroot "${mountpt}" systemctl disable systemd-networkd-wait-online

  # disable sshd until after keys are regenerated on first boot
  rm -fv "${mountpt}/etc/systemd/system/sshd.service"
  rm -fv "${mountpt}/etc/systemd/system/multi-user.target.wants/ssh.service"
  rm -fv "${mountpt}/etc/ssh/ssh_host_"*

  # generate machine id on first boot
  rm -fv "${mountpt}/etc/machine-id"

  umount "${mountpt}"
  rm -rf "${mountpt}"

  echo "installing u-boot"
  dd bs=4K seek=8 if="${uboot_spl}" of="${image_file}" conv=notrunc
  dd bs=4K seek=2048 if="${uboot_itb}" of="${image_file}" conv=notrunc,fsync

  if [ "${compress}" != "nocomp" ]; then
    echo "compressing image file"
    xz -z8vc "${image_file}" > "${image_file}".xz

    # compress image copy
    mkdir -p "${mountpt}"
    mount -no loop,offset=16M "${image_file}" "${mountpt}"
    cp -p "${image_file}".xz "${mountpt}"
    umount "${mountpt}"
    rm -rf "${mountpt}"

    echo -e "\ncompressed image is now ready"
    echo -e "\ncopy image to target media:"
    echo "  sudo sh -c 'xzcat ${image_file}.xz > /dev/sdX && sync'"
  fi
