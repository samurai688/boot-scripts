#!/bin/bash -e
#
# Copyright (c) 2013-2015 Robert Nelson <robertcnelson@gmail.com>
# Portions copyright (c) 2014 Charles Steinkuehler <charles@steinkuehler.net>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#This script assumes, these packages are installed, as network may not be setup
#dosfstools initramfs-tools rsync u-boot-tools

#WARNING make sure to run this with an initrd...
#lsmod:
#Module                  Size  Used by
#uas                    14300  0 
#usb_storage            53318  1 uas

#job.txt
#abi=aaa
#conf_image=
#conf_bmap=

if ! id | grep -q root; then
	echo "must be run as root"
	exit
fi

unset root_drive
root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root=UUID= | awk -F 'root=' '{print $2}' || true)"
if [ ! "x${root_drive}" = "x" ] ; then
	root_drive="$(/sbin/findfs ${root_drive} || true)"
else
	root_drive="$(cat /proc/cmdline | sed 's/ /\n/g' | grep root= | awk -F 'root=' '{print $2}' || true)"
fi

mount -t tmpfs tmpfs /tmp

destination="/dev/mmcblk1"
usb_drive="/dev/sda"

flush_cache () {
	sync
	blockdev --flushbufs ${destination}
}

broadcast () {
	if [ "x${message}" != "x" ] ; then
		echo "${message}"
		echo "${message}" > /dev/tty0 || true
	fi
}

inf_loop () {
	while read MAGIC ; do
		case $MAGIC in
		beagleboard.org)
			echo "Your foo is strong!"
			bash -i
			;;
		*)	echo "Your foo is weak."
			;;
		esac
	done
}

# umount does not like device names without a valid /etc/mtab
# find the mount point from /proc/mounts
dev2dir () {
	grep -m 1 '^$1 ' /proc/mounts | while read LINE ; do set -- $LINE ; echo $2 ; done
}

write_failure () {
	message="writing to [${destination}] failed..." ; broadcast

	[ -e /proc/$CYLON_PID ]  && kill $CYLON_PID > /dev/null 2>&1

	if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr0/trigger
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr1/trigger
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr2/trigger
		echo heartbeat > /sys/class/leds/beaglebone\:green\:usr3/trigger
	fi
	message="-----------------------------" ; broadcast
	flush_cache
	umount $(dev2dir ${destination}p1) > /dev/null 2>&1 || true
	umount $(dev2dir ${destination}p2) > /dev/null 2>&1 || true
	inf_loop
}

print_eeprom () {
	message="Checking EEPROM:" ; broadcast

	if [ -f /sys/class/nvmem/at24-0/nvmem ] ; then
		message="4.1.x+ kernel with nvmem detected..." ; broadcast
		eeprom="/sys/class/nvmem/at24-0/nvmem"

		#with 4.1.x: -s 5 isn't working...
		#eeprom_header=$(hexdump -e '8/1 "%c"' ${eeprom} -s 5 -n 3) = blank...
		#hexdump -e '8/1 "%c"' ${eeprom} -n 8 = �U3�A335
		eeprom_header=$(hexdump -e '8/1 "%c"' ${eeprom} -n 28 | cut -b 5-28)

		eeprom_location="/sys/devices/platform/ocp/44e0b000.i2c/i2c-0/0-0050/nvmem/at24-0/nvmem"
	else
		eeprom="/sys/bus/i2c/devices/0-0050/eeprom"
		eeprom_header=$(hexdump -e '8/1 "%c"' ${eeprom} -s 5 -n 25)
		eeprom_location=$(ls /sys/devices/ocp*/44e0b000.i2c/i2c-0/0-0050/eeprom 2> /dev/null)
	fi

	message="Current EEPROM: [${eeprom_header}]" ; broadcast
	message="-----------------------------" ; broadcast
}

flash_emmc () {
	if [ -f /usr/bin/bmaptool ] && [ -f /tmp/usb/${conf_bmap} ] ; then
		message="Flashing eMMC with bmaptool" ; broadcast
		message="-----------------------------" ; broadcast
		message="bmaptool copy --bmap /tmp/usb/${conf_bmap} /tmp/usb/${conf_image} ${destination}" ; broadcast
		/usr/bin/bmaptool copy --bmap /tmp/usb/${conf_bmap} /tmp/usb/${conf_image} ${destination}
		message="-----------------------------" ; broadcast
	else
		message="Flashing eMMC with dd" ; broadcast
		message="-----------------------------" ; broadcast
		message="xzcat /tmp/usb/${conf_image} | dd of=${destination} bs=1M" ; broadcast
		xzcat /tmp/usb/${conf_image} | dd of=${destination} bs=1M
		message="-----------------------------" ; broadcast
	fi
}

quad_partition () {
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message=",${conf_partition2_endmb},${conf_partition2_fstype},-" ; broadcast
	message=",${conf_partition3_endmb},${conf_partition3_fstype},-" ; broadcast
	message=",,${conf_partition4_fstype},-" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*
		,${conf_partition2_endmb},${conf_partition2_fstype},-
		,${conf_partition3_endmb},${conf_partition3_fstype},-
		,,${conf_partition4_fstype},-
	__EOF__

	message="-----------------------------" ; broadcast
	message="e2fsck -f ${destination}p1" ; broadcast
	e2fsck -f ${destination}p1
	message="e2fsck -f ${destination}p2" ; broadcast
	e2fsck -f ${destination}p2
	message="e2fsck -f ${destination}p3" ; broadcast
	e2fsck -f ${destination}p3
	message="e2fsck -f ${destination}p4" ; broadcast
	e2fsck -f ${destination}p4
	message="resize2fs ${destination}p4" ; broadcast
	resize2fs ${destination}p4
	message="-----------------------------" ; broadcast
}

tri_partition () {
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message=",${conf_partition2_endmb},${conf_partition2_fstype},-" ; broadcast
	message=",,${conf_partition3_fstype},-" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*
		,${conf_partition2_endmb},${conf_partition2_fstype},-
		,,${conf_partition3_fstype},-
	__EOF__

	message="-----------------------------" ; broadcast
	message="e2fsck -f ${destination}p1" ; broadcast
	e2fsck -f ${destination}p1
	message="e2fsck -f ${destination}p2" ; broadcast
	e2fsck -f ${destination}p2
	message="e2fsck -f ${destination}p3" ; broadcast
	e2fsck -f ${destination}p3
	message="resize2fs ${destination}p3" ; broadcast
	resize2fs ${destination}p3
	message="-----------------------------" ; broadcast
}

dual_partition () {
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message=",,${conf_partition2_fstype},-" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*
		,,${conf_partition2_fstype},-
	__EOF__

	message="-----------------------------" ; broadcast
	message="e2fsck -f ${destination}p1" ; broadcast
	e2fsck -f ${destination}p1
	message="e2fsck -f ${destination}p2" ; broadcast
	e2fsck -f ${destination}p2
	message="resize2fs ${destination}p2" ; broadcast
	resize2fs ${destination}p2
	message="-----------------------------" ; broadcast
}

single_partition () {
	message="LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination}" ; broadcast
	message="${conf_partition1_startmb},${conf_partition1_endmb},${conf_partition1_fstype},*" ; broadcast
	message="-----------------------------" ; broadcast

	LC_ALL=C sfdisk --force --no-reread --in-order --Linux --unit M ${destination} <<-__EOF__
		${conf_partition1_startmb},,${conf_partition1_fstype},*
	__EOF__

	message="-----------------------------" ; broadcast
	message="e2fsck -f ${destination}p1" ; broadcast
	e2fsck -f ${destination}p1
	message="resize2fs ${destination}p1" ; broadcast
	resize2fs ${destination}p1
	message="-----------------------------" ; broadcast
}

resize_emmc () {
	unset resized

	conf_partition1_startmb=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition1_startmb | awk -F '=' '{print $2}' || true)
	conf_partition1_fstype=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition1_fstype | awk -F '=' '{print $2}' || true)
	conf_partition1_endmb=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition1_endmb | awk -F '=' '{print $2}' || true)

	conf_partition2_fstype=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition2_fstype | awk -F '=' '{print $2}' || true)
	conf_partition2_endmb=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition2_endmb | awk -F '=' '{print $2}' || true)

	conf_partition3_fstype=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition3_fstype | awk -F '=' '{print $2}' || true)
	conf_partition3_endmb=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition3_endmb | awk -F '=' '{print $2}' || true)

	conf_partition4_fstype=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_partition4_fstype | awk -F '=' '{print $2}' || true)

	if [ ! "x${conf_partition4_fstype}" = "x" ] ; then
		quad_partition
		resized="done"
	fi

	if [ ! "x${conf_partition3_fstype}" = "x" ] && [ ! "x${resized}" = "xdone" ] ; then
		tri_partition
		resized="done"
	fi

	if [ ! "x${conf_partition2_fstype}" = "x" ] && [ ! "x${resized}" = "xdone" ] ; then
		dual_partition
		resized="done"
	fi

	if [ ! "x${conf_partition1_fstype}" = "x" ] && [ ! "x${resized}" = "xdone" ] ; then
		single_partition
		resized="done"
	fi
}

set_uuid () {
	unset root_uuid
	root_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${destination}p${conf_root_partition} || true)
	mkdir -p /tmp/rootfs/
	mkdir -p /tmp/boot/

	mount ${destination}p${conf_root_partition} /tmp/rootfs/ -o async,noatime
	sleep 2

	if [ ! "x${conf_root_partition}" = "x1" ] ; then
		mount ${destination}p1 /tmp/boot/ -o sync
		sleep 2
	fi

	if [ -f /tmp/rootfs/boot/uEnv.txt ] && [ -f /tmp/boot/uEnv.txt ] ; then
		rm -f /tmp/boot/uEnv.txt
		umount /tmp/boot/ || umount -l /tmp/boot/ || write_failure
	fi

	if [ -f /tmp/rootfs/boot/uEnv.txt ] && [ -f /tmp/rootfs/uEnv.txt ] ; then
		rm -f /tmp/rootfs/uEnv.txt
	fi

	unset uuid_uevntxt
	uuid_uevntxt=$(cat /tmp/rootfs/boot/uEnv.txt | grep -v '#' | grep uuid | awk -F '=' '{print $2}' || true)
	if [ ! "x${uuid_uevntxt}" = "x" ] ; then
		sed -i -e "s:uuid=$uuid_uevntxt:uuid=$root_uuid:g" /tmp/rootfs/boot/uEnv.txt
	else
		sed -i -e "s:#uuid=:uuid=$root_uuid:g" /tmp/rootfs/boot/uEnv.txt
		unset uuid_uevntxt
		uuid_uevntxt=$(cat /tmp/rootfs/boot/uEnv.txt | grep -v '#' | grep uuid | awk -F '=' '{print $2}' || true)
		if [ "x${uuid_uevntxt}" = "x" ] ; then
			echo "uuid=${root_uuid}" >> /tmp/rootfs/boot/uEnv.txt
		fi
	fi
	message="`cat /tmp/rootfs/boot/uEnv.txt`" ; broadcast
	message="-----------------------------" ; broadcast

	message="UUID=${root_uuid}" ; broadcast
	root_uuid="UUID=${root_uuid}"

	message="Generating: /etc/fstab" ; broadcast
	echo "# /etc/fstab: static file system information." > /tmp/rootfs/etc/fstab
	echo "#" >> /tmp/rootfs/etc/fstab
	echo "${root_uuid}  /  ext4  noatime,errors=remount-ro  0  1" >> /tmp/rootfs/etc/fstab
	echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> /tmp/rootfs/etc/fstab
	message="`cat /tmp/rootfs/etc/fstab`" ; broadcast
	message="-----------------------------" ; broadcast


	umount /tmp/rootfs/ || umount -l /tmp/rootfs/ || write_failure
}

process_job_file () {
	job_file=found
	message="Processing job.txt" ; broadcast
	message="job.txt:" ; broadcast
	message="`cat /tmp/usb/job.txt | grep -v '#'`" ; broadcast
	message="-----------------------------" ; broadcast

	abi=$(cat /tmp/usb/job.txt | grep -v '#' | grep abi | awk -F '=' '{print $2}' || true)
	if [ "x${abi}" = "xaaa" ] ; then
		conf_image=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_image | awk -F '=' '{print $2}' || true)
		conf_bmap=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_bmap | awk -F '=' '{print $2}' || true)
		if [ -f /tmp/usb/${conf_image} ] ; then
			flash_emmc
			conf_resize=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_resize | awk -F '=' '{print $2}' || true)
			if [ "x${conf_resize}" = "xenable" ] ; then
				message="resizing eMMC" ; broadcast
				message="-----------------------------" ; broadcast
				resize_emmc
			fi
			conf_root_partition=$(cat /tmp/usb/job.txt | grep -v '#' | grep conf_root_partition | awk -F '=' '{print $2}' || true)
			if [ ! "x${conf_root_partition}" = "x" ] ; then
				set_uuid
			fi
		else
			message="error: image not found [/tmp/usb/${conf_image}]" ; broadcast
		fi
	fi
}

check_usb_media () {
	message="Checking external usb media" ; broadcast
	message="lsblk:" ; broadcast
	message="`lsblk || true`" ; broadcast
	message="-----------------------------" ; broadcast
	unset job_file

	num_partitions=$(LC_ALL=C fdisk -l 2>/dev/null | grep "^${usb_drive}" | grep -v "Extended" | grep -v "swap" | wc -l)

	i=0 ; while test $i -le ${num_partitions} ; do
		partition=$(LC_ALL=C fdisk -l 2>/dev/null | grep "^${usb_drive}" | grep -v "Extended" | grep -v "swap" | head -${i} | tail -1 | awk '{print $1}')
		if [ ! "x${partition}" = "x" ] ; then
			message="Trying: [${partition}]" ; broadcast

			mkdir -p "/tmp/usb/"
			mount ${partition} "/tmp/usb/" -o ro

			sync ; sync ; sleep 5

			if [ ! -f /tmp/usb/job.txt ] ; then
				umount "/tmp/usb/" || true
			else
				process_job_file
			fi

		fi
	i=$(($i+1))
	done

	if [ ! "x${job_file}" = "xfound" ] ; then
		message="job.txt: format" ; broadcast
		message="-----------------------------" ; broadcast
		message="abi=aaa" ; broadcast
		message="conf_image=<file>.img.xz" ; broadcast
		message="conf_bmap=<file>.bmap" ; broadcast
		message="conf_resize=enable|<blank>" ; broadcast
		message="conf_partition1_startmb=1" ; broadcast
		message="conf_partition1_fstype=" ; broadcast

		message="#last endmb is ignored as it just uses the rest of the drive..." ; broadcast
		message="conf_partition1_endmb=" ; broadcast

		message="conf_partition2_fstype=" ; broadcast
		message="conf_partition2_endmb=" ; broadcast

		message="conf_partition3_fstype=" ; broadcast
		message="conf_partition3_endmb=" ; broadcast

		message="conf_partition4_fstype=" ; broadcast

		message="conf_root_partition=1|2|3|4" ; broadcast
		message="-----------------------------" ; broadcast
		sleep 100
	fi

	message="eMMC has been flashed: please wait for device to power down." ; broadcast
	message="-----------------------------" ; broadcast

	sleep 20

	#To properly shudown, /opt/scripts/boot/am335x_evm.sh is going to call halt:
	exec /sbin/init
	#halt -f
}

check_running_system () {
	message="copying: [${source}] -> [${destination}]" ; broadcast
	message="lsblk:" ; broadcast
	message="`lsblk || true`" ; broadcast
	message="-----------------------------" ; broadcast
	message="df -h | grep rootfs:" ; broadcast
	message="`df -h | grep rootfs || true`" ; broadcast
	message="-----------------------------" ; broadcast

	if [ ! -b "${destination}" ] ; then
		message="Error: [${destination}] does not exist" ; broadcast
		write_failure
	fi

	##FIXME: quick check for rsync 3.1 (jessie)
	unset rsync_check
	unset rsync_progress
	rsync_check=$(LC_ALL=C rsync --version | grep version | awk '{print $3}' || true)
	if [ "x${rsync_check}" = "x3.1.1" ] ; then
		rsync_progress="--info=progress2 --human-readable"
	fi

	if [ ! -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
		modprobe leds_gpio || true
		sleep 1
	fi
}

cylon_leds () {
	if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
		BASE=/sys/class/leds/beaglebone\:green\:usr
		echo none > ${BASE}0/trigger
		echo none > ${BASE}1/trigger
		echo none > ${BASE}2/trigger
		echo none > ${BASE}3/trigger

		STATE=1
		while : ; do
			case $STATE in
			1)	echo 255 > ${BASE}0/brightness
				echo 0   > ${BASE}1/brightness
				STATE=2
				;;
			2)	echo 255 > ${BASE}1/brightness
				echo 0   > ${BASE}0/brightness
				STATE=3
				;;
			3)	echo 255 > ${BASE}2/brightness
				echo 0   > ${BASE}1/brightness
				STATE=4
				;;
			4)	echo 255 > ${BASE}3/brightness
				echo 0   > ${BASE}2/brightness
				STATE=5
				;;
			5)	echo 255 > ${BASE}2/brightness
				echo 0   > ${BASE}3/brightness
				STATE=6
				;;
			6)	echo 255 > ${BASE}1/brightness
				echo 0   > ${BASE}2/brightness
				STATE=1
				;;
			*)	echo 255 > ${BASE}0/brightness
				echo 0   > ${BASE}1/brightness
				STATE=2
				;;
			esac
			sleep 0.1
		done
	fi
}

dd_bootloader () {
	message="Writing bootloader to [${destination}]" ; broadcast

	unset dd_spl_uboot
	if [ ! "x${dd_spl_uboot_count}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}count=${dd_spl_uboot_count} "
	fi

	if [ ! "x${dd_spl_uboot_seek}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}seek=${dd_spl_uboot_seek} "
	fi

	if [ ! "x${dd_spl_uboot_conf}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}conv=${dd_spl_uboot_conf} "
	fi

	if [ ! "x${dd_spl_uboot_bs}" = "x" ] ; then
		dd_spl_uboot="${dd_spl_uboot}bs=${dd_spl_uboot_bs}"
	fi

	unset dd_uboot
	if [ ! "x${dd_uboot_count}" = "x" ] ; then
		dd_uboot="${dd_uboot}count=${dd_uboot_count} "
	fi

	if [ ! "x${dd_uboot_seek}" = "x" ] ; then
		dd_uboot="${dd_uboot}seek=${dd_uboot_seek} "
	fi

	if [ ! "x${dd_uboot_conf}" = "x" ] ; then
		dd_uboot="${dd_uboot}conv=${dd_uboot_conf} "
	fi

	if [ ! "x${dd_uboot_bs}" = "x" ] ; then
		dd_uboot="${dd_uboot}bs=${dd_uboot_bs}"
	fi

	message="dd if=${dd_spl_uboot_backup} of=${destination} ${dd_spl_uboot}" ; broadcast
	echo "-----------------------------"
	dd if=${dd_spl_uboot_backup} of=${destination} ${dd_spl_uboot}
	echo "-----------------------------"
	message="dd if=${dd_uboot_backup} of=${destination} ${dd_uboot}" ; broadcast
	echo "-----------------------------"
	dd if=${dd_uboot_backup} of=${destination} ${dd_uboot}
	message="-----------------------------" ; broadcast
}

format_boot () {
	message="mkfs.vfat -F 16 ${destination}p1 -n ${boot_label}" ; broadcast
	echo "-----------------------------"
	mkfs.vfat -F 16 ${destination}p1 -n ${boot_label}
	echo "-----------------------------"
	flush_cache
}

format_root () {
	message="mkfs.ext4 ${destination}p2 -L ${rootfs_label}" ; broadcast
	echo "-----------------------------"
	mkfs.ext4 ${destination}p2 -L ${rootfs_label}
	echo "-----------------------------"
	flush_cache
}

format_single_root () {
	message="mkfs.ext4 ${destination}p1 -L ${boot_label}" ; broadcast
	echo "-----------------------------"
	mkfs.ext4 ${destination}p1 -L ${boot_label}
	echo "-----------------------------"
	flush_cache
}

copy_boot () {
	message="Copying: ${source}p1 -> ${destination}p1" ; broadcast
	mkdir -p /tmp/boot/ || true

	mount ${destination}p1 /tmp/boot/ -o sync

	if [ -f /boot/uboot/MLO ] ; then
		#Make sure the BootLoader gets copied first:
		cp -v /boot/uboot/MLO /tmp/boot/MLO || write_failure
		flush_cache

		cp -v /boot/uboot/u-boot.img /tmp/boot/u-boot.img || write_failure
		flush_cache
	fi

	message="rsync: /boot/uboot/ -> /tmp/boot/" ; broadcast
	if [ ! "x${rsync_progress}" = "x" ] ; then
		echo "rsync: note the % column is useless..."
	fi
	rsync -aAx ${rsync_progress} /boot/uboot/ /tmp/boot/ --exclude={MLO,u-boot.img,uEnv.txt} || write_failure
	flush_cache

	flush_cache
	umount /tmp/boot/ || umount -l /tmp/boot/ || write_failure
	flush_cache
	umount /boot/uboot || umount -l /boot/uboot
}

copy_rootfs () {
	message="Copying: ${source}p${media_rootfs} -> ${destination}p${media_rootfs}" ; broadcast
	mkdir -p /tmp/rootfs/ || true

	mount ${destination}p${media_rootfs} /tmp/rootfs/ -o async,noatime

	message="rsync: / -> /tmp/rootfs/" ; broadcast
	if [ ! "x${rsync_progress}" = "x" ] ; then
		echo "rsync: note the % column is useless..."
	fi
	rsync -aAx ${rsync_progress} /* /tmp/rootfs/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found,/lib/modules/*,/uEnv.txt} || write_failure
	flush_cache

	if [ -d /tmp/rootfs/etc/ssh/ ] ; then
		#ssh keys will now get regenerated on the next bootup
		touch /tmp/rootfs/etc/ssh/ssh.regenerate
		flush_cache
	fi

	mkdir -p /tmp/rootfs/lib/modules/$(uname -r)/ || true

	message="Copying: Kernel modules" ; broadcast
	message="rsync: /lib/modules/$(uname -r)/ -> /tmp/rootfs/lib/modules/$(uname -r)/" ; broadcast
	if [ ! "x${rsync_progress}" = "x" ] ; then
		echo "rsync: note the % column is useless..."
	fi
	rsync -aAx ${rsync_progress} /lib/modules/$(uname -r)/* /tmp/rootfs/lib/modules/$(uname -r)/ || write_failure
	flush_cache

	message="Copying: ${source}p${media_rootfs} -> ${destination}p${media_rootfs} complete" ; broadcast
	message="-----------------------------" ; broadcast

	message="Final System Tweaks:" ; broadcast
	unset root_uuid
	root_uuid=$(/sbin/blkid -c /dev/null -s UUID -o value ${destination}p${media_rootfs})
	if [ "${root_uuid}" ] ; then
		sed -i -e 's:uuid=:#uuid=:g' /tmp/rootfs/boot/uEnv.txt
		echo "uuid=${root_uuid}" >> /tmp/rootfs/boot/uEnv.txt

		message="UUID=${root_uuid}" ; broadcast
		root_uuid="UUID=${root_uuid}"
	else
		#really a failure...
		root_uuid="${source}p${media_rootfs}"
	fi

	message="Generating: /etc/fstab" ; broadcast
	echo "# /etc/fstab: static file system information." > /tmp/rootfs/etc/fstab
	echo "#" >> /tmp/rootfs/etc/fstab
	echo "${root_uuid}  /  ext4  noatime,errors=remount-ro  0  1" >> /tmp/rootfs/etc/fstab
	echo "debugfs  /sys/kernel/debug  debugfs  defaults  0  0" >> /tmp/rootfs/etc/fstab
	cat /tmp/rootfs/etc/fstab

	message="/boot/uEnv.txt: disabling eMMC flasher script" ; broadcast
	script="cmdline=init=/opt/scripts/tools/eMMC/init-eMMC-flasher-v3.sh"
	sed -i -e 's:'$script':#'$script':g' /tmp/rootfs/boot/uEnv.txt
	cat /tmp/rootfs/boot/uEnv.txt
	message="-----------------------------" ; broadcast

	flush_cache
	umount /tmp/rootfs/ || umount -l /tmp/rootfs/ || write_failure

	[ -e /proc/$CYLON_PID ]  && kill $CYLON_PID

	message="Syncing: ${destination}" ; broadcast
	#https://github.com/beagleboard/meta-beagleboard/blob/master/contrib/bone-flash-tool/emmc.sh#L158-L159
	# force writeback of eMMC buffers
	sync
	dd if=${destination} of=/dev/null count=100000
	message="Syncing: ${destination} complete" ; broadcast
	message="-----------------------------" ; broadcast

	if [ -f /boot/debug.txt ] ; then
		message="This script has now completed its task" ; broadcast
		message="-----------------------------" ; broadcast
		message="debug: enabled" ; broadcast
		inf_loop
	else
		umount /tmp || umount -l /tmp
		if [ -e /sys/class/leds/beaglebone\:green\:usr0/trigger ] ; then
			echo default-on > /sys/class/leds/beaglebone\:green\:usr0/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr1/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr2/trigger
			echo default-on > /sys/class/leds/beaglebone\:green\:usr3/trigger
		fi
		mount

		message="eMMC has been flashed: please wait for device to power down." ; broadcast
		message="-----------------------------" ; broadcast

		flush_cache
		#To properly shudown, /opt/scripts/boot/am335x_evm.sh is going to call halt:
		exec /sbin/init
		#halt -f
	fi
}

partition_drive () {
	message="Erasing: ${destination}" ; broadcast
	flush_cache
	dd if=/dev/zero of=${destination} bs=1M count=108
	sync
	dd if=${destination} of=/dev/null bs=1M count=108
	sync
	flush_cache
	message="Erasing: ${destination} complete" ; broadcast
	message="-----------------------------" ; broadcast

	if [ -f /boot/SOC.sh ] ; then
		. /boot/SOC.sh
	fi

	dd_bootloader

	if [ "x${boot_fstype}" = "xfat" ] ; then
		conf_boot_startmb=${conf_boot_startmb:-"1"}
		conf_boot_endmb=${conf_boot_endmb:-"96"}
		sfdisk_fstype=${sfdisk_fstype:-"0xE"}
		boot_label=${boot_label:-"BEAGLEBONE"}
		rootfs_label=${rootfs_label:-"rootfs"}

		message="Formatting: ${destination}" ; broadcast

		sfdisk_options="--force --Linux --in-order --unit M"
		sfdisk_boot_startmb="${conf_boot_startmb}"
		sfdisk_boot_endmb="${conf_boot_endmb}"

		test_sfdisk=$(LC_ALL=C sfdisk --help | grep -m 1 -e "--in-order" || true)
		if [ "x${test_sfdisk}" = "x" ] ; then
			message="sfdisk: [2.26.x or greater]" ; broadcast
			sfdisk_options="--force"
			sfdisk_boot_startmb="${sfdisk_boot_startmb}M"
			sfdisk_boot_endmb="${sfdisk_boot_endmb}M"
		fi

		message="sfdisk: [sfdisk ${sfdisk_options} ${destination}]" ; broadcast
		message="sfdisk: [${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*]" ; broadcast
		message="sfdisk: [,,,-]" ; broadcast

		LC_ALL=C sfdisk ${sfdisk_options} "${destination}" <<-__EOF__
			${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*
			,,,-
		__EOF__

		flush_cache
		format_boot
		format_root
		message="Formatting: ${destination} complete" ; broadcast
		message="-----------------------------" ; broadcast

		copy_boot
		media_rootfs="2"
		copy_rootfs
	else
		conf_boot_startmb=${conf_boot_startmb:-"1"}
		sfdisk_fstype=${sfdisk_fstype:-"0x83"}
		boot_label=${boot_label:-"BEAGLEBONE"}

		message="Formatting: ${destination}" ; broadcast

		sfdisk_options="--force --Linux --in-order --unit M"
		sfdisk_boot_startmb="${conf_boot_startmb}"

		test_sfdisk=$(LC_ALL=C sfdisk --help | grep -m 1 -e "--in-order" || true)
		if [ "x${test_sfdisk}" = "x" ] ; then
			message="sfdisk: [2.26.x or greater]" ; broadcast
			sfdisk_options="--force"
			sfdisk_boot_startmb="${sfdisk_boot_startmb}M"
		fi

		message="sfdisk: [sfdisk ${sfdisk_options} ${destination}]" ; broadcast
		message="sfdisk: [${sfdisk_boot_startmb},${sfdisk_boot_endmb},${sfdisk_fstype},*]" ; broadcast

		LC_ALL=C sfdisk ${sfdisk_options} "${destination}" <<-__EOF__
			${sfdisk_boot_startmb},,${sfdisk_fstype},*
		__EOF__

		flush_cache
		format_single_root
		message="Formatting: ${destination} complete" ; broadcast
		message="-----------------------------" ; broadcast

		media_rootfs="1"
		copy_rootfs
	fi
}

sleep 5
clear
message="-----------------------------" ; broadcast
message="Starting eMMC Flasher from usb media" ; broadcast
message="-----------------------------" ; broadcast

print_eeprom
check_usb_media
#check_eeprom
#check_running_system
#cylon_leds & CYLON_PID=$!
#partition_drive
#
