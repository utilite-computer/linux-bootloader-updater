#! /bin/bash
#
# CompuLab CM-FX6 module boot loader update utility
#
# Copyright (C) 2013 CompuLab, Ltd.
# Author: Igor Grinberg <grinberg@compulab.co.il>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

UPDATER_VERSION="1.2"
UPDATER_VERSION_DATE="Dec 09 2013"
UPDATER_BANNER="CompuLab CM-FX6 (Utilite) boot loader update utility ${UPDATER_VERSION} (${UPDATER_VERSION_DATE})"

NORMAL="\033[0m"
WARN="\033[33;1m"
BAD="\033[31;1m"
BOLD="\033[1m"
GOOD="\033[32;1m"

function good_msg() {
	msg_string=$1
	msg_string="${msg_string:-...}"
	echo -e "${GOOD}>>${NORMAL}${BOLD} ${msg_string} ${NORMAL}"
}

function bad_msg() {
	msg_string=$1
	msg_string="${msg_string:-...}"
	echo -e "${BAD}!!${NORMAL}${BOLD} ${msg_string} ${NORMAL}"
}

function warn_msg() {
	msg_string=$1
	msg_string="${msg_string:-...}"
	echo -e "${WARN}**${NORMAL}${BOLD} ${msg_string} ${NORMAL}"
}

function DD() {
	dd $* &> /dev/null & pid=$!

	while [ -e /proc/$pid ] ; do
		echo -n "."
		sleep 1
	done

	echo ""
	wait $pid
	return $?
}

MTD_DEV="mtd0"
MTD_DEV_FILE="/dev/${MTD_DEV}"
CPU_NAME=""
DRAM_NAME=""
BOOTLOADER_FILE="cm-fx6-firmware"

function find_bootloader_file() {
	good_msg "Looking for boot loader image file: $BOOTLOADER_FILE"

	if [ ! -s $BOOTLOADER_FILE ]; then
		bad_msg "Can't find boot loader image file for the board"
		return 1;
	fi

	good_msg "...Found"
	return 0;
}

function check_spi_flash() {
	good_msg "Looking for SPI flash: $MTD_DEV"

	grep -qE "$MTD_DEV: [0-f]+ [0-f]+ \"uboot\"" /proc/mtd
	if [ $? -ne 0 ]; then
		bad_msg "Can't find $MTD_DEV device, is the SPI flash support enabled in kernel?"
		return 1;
	fi

	if [ ! -c $MTD_DEV_FILE ]; then
		bad_msg "Can't find $MTD_DEV device special file: $MTD_DEV_FILE"
		return 1;
	fi

	good_msg "...Found"
	return 0;
}

function get_uboot_version() {
	local file="$1"
	grep -oazE "U-Boot [0-9]+\.[0-9]+.* \(... +[0-9]+ [0-9]+ - [0-9]+:[0-9]+:[0-9]+\)" "$file"
}

function check_bootloader_versions() {
	local flash_version=`echo \`get_uboot_version $MTD_DEV_FILE\``
	local file_version=`echo \`get_uboot_version $BOOTLOADER_FILE\``
	local file_size=`du -hL $BOOTLOADER_FILE | cut -f1`

	good_msg "Current U-Boot version in SPI flash:\t$flash_version"
	good_msg "New U-Boot version in file:\t\t$file_version ($file_size)"

	good_msg "Proceed with the update?"
	select yn in "Yes" "No"; do
		case $yn in
			"Yes")
				return 0;
				;;
			"No")
				return 1;
				;;
			*)
				case ${REPLY,,} in
					"y"|"yes")
						return 0;
						;;
					"n"|"no"|"abort")
						return 1;
						;;
				esac
		esac
	done

	return 1;
}

function check_utility() {
	local util_name="$1"
	local utility=`which "$util_name"`

	if [[ -z "$utility" || ! -x $utility ]]; then
		bad_msg "Can't find $util_name utility! Please install $util_name before proceding!"
		return 1;
	fi

	return 0;
}

function check_utilities() {
	good_msg "Checking for utilities..."

	check_utility "diff"		|| return 1;
	check_utility "grep"		|| return 1;
	check_utility "sed"		|| return 1;
	check_utility "hexdump"		|| return 1;
	check_utility "dd"		|| return 1;
	check_utility "flash_erase"	|| return 1;

	good_msg "...Done"
	return 0;
}

function erase_spi_flash() {
	good_msg "Erasing SPI flash..."

	flash_erase $MTD_DEV_FILE 0 0
	if [ $? -ne 0 ]; then
		bad_msg "Failed erasing SPI flash!"
		bad_msg "If you reboot, your system might not boot anymore!"
		bad_msg "Please, try re-installing mtd-utils package and retry!"
		return 1;
	fi

	good_msg "...Done"
	return 0;
}

function write_bootloader() {
	good_msg "Writing boot loader to the SPI flash..."

	DD if=$BOOTLOADER_FILE of=$MTD_DEV_FILE
	if [ $? -ne 0 ]; then
		bad_msg "Failed writing boot loader to the SPI flash!"
		bad_msg "If you reboot, your system might not boot anymore!"
		bad_msg "Please, try re-installing mtd-utils package and retry!"
		return 1;
	fi

	good_msg "...Done"
	return 0;
}

function check_bootloader() {
	good_msg "Checking boot loader in the SPI flash..."

	local test_file="${BOOTLOADER_FILE}.test"
	local size=`du -bL $BOOTLOADER_FILE | cut -f1`

	DD if=$MTD_DEV_FILE of=$test_file bs=$size count=1

	diff $BOOTLOADER_FILE $test_file > /dev/null
	if [ $? -ne 0 ]; then
		bad_msg "Boot loader check failed! Please retry the update procedure!"
		return 1;
	fi

	rm -f $test_file

	good_msg "...Done"
	return 0;
}

function error_exit() {
	bad_msg "Boot loader update failed!"
	exit $1;
}

#main()
echo -e "\n${UPDATER_BANNER}\n"

check_utilities			|| error_exit 4;
find_bootloader_file		|| error_exit 1;
check_spi_flash			|| error_exit 2;
check_bootloader_versions	|| exit 0;

warn_msg "Do not power off or reset your computer!!!"

erase_spi_flash			|| error_exit 5;
write_bootloader		|| error_exit 6;
check_bootloader		|| error_exit 7;

good_msg "Boot loader update succeeded!\n"

