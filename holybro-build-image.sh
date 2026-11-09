#!/bin/bash
# Build a Holybro Pixhawk Jetson baseboard image for Jetson Orin NX.
# JetPack 6.2.2 (L4T 36.5.0) uses the target name jetson-orin-nano-devkit-super.
# The image also gets the JetPack 6.2.2 runtime and development packages (versions from
# jetpack-6.2.2.list, the same set as the holybro-dev-env sysroot; see jetson-install-dev.sh),
# a default user, English locale and keyboard, so the board is usable right after flashing.
#
# This script only generates images. It never writes the board, and by default it
# does not need the board connected: the board identity is passed as environment
# variables below, so the long USB session that caused write errors is avoided.
# Writing is done separately by holybro-flash-image.sh with the same work directory.
#
# Usage:
#   holybro-build-image.sh [-w DIR] [--force] [--with-board]
#     -w DIR        work directory for downloads, Linux_for_Tegra and images
#                   (default: WORK_DIR, else the current directory)
#     --force       delete existing images and generate again
#     --with-board  generate while reading the board in REC at 480 Mbps
#                   (use once to learn CHIP_SKU and RAMCODE_ID)
# The full log is saved to build-image.log in the work directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="jetson-orin-nano-devkit-super"
BSP_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/release/Jetson_Linux_r36.5.0_aarch64.tbz2"
ROOTFS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/release/Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2"
PATCH_URL="https://2367252986-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FLIgtGDAvVGkCKGOJb1bR%2Fuploads%2FJRxHWde4kntHcgKoUTmO%2Fholybro_jp622.tbz2?alt=media&token=cab3e1cd-d017-43bc-bbfd-1c4650bb03cc"
BSP_TBZ="Jetson_Linux_r36.5.0_aarch64.tbz2"
ROOTFS_TBZ="Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2"
PATCH_TBZ="holybro_jp622.tbz2"

# JetPack runtime. The NVIDIA r36.5 repository also has 6.2.3 (L4T 36.5.2), so every
# version is pinned. The list is the same file holybro-dev-env builds its sysroot from.
JETPACK_VERSION="6.2.2+b24"
PIN_LIST="${SCRIPT_DIR}/jetpack-6.2.2.list"
DEV_SCRIPT="${SCRIPT_DIR}/jetson-install-dev.sh"

# Default user and system settings written into the image.
JETSON_USER="${JETSON_USER:-dev}"
JETSON_PASSWORD="${JETSON_PASSWORD:-roqkf}"
JETSON_HOSTNAME="${JETSON_HOSTNAME:-jetson}"
JETSON_TIMEZONE="${JETSON_TIMEZONE:-Asia/Seoul}"

# Board identity for generating without the board. Override with environment variables.
# Read from the running Orin NX 16GB board:
#   BOARDID, FAB, BOARDSKU, BOARDREV  /etc/nv_boot_control.conf TNSPEC 3767-303-0000-F.1-1-1
#   CHIP_SKU                          kernel log "Tegra Revision: A01 SKU: 211" (211 = 0xD3)
#   FUSELEVEL                         TNSPEC fuse level 1 = production
#   RAMCODE_ID                        flash.sh --no-flash in REC: "Ram code: 0x1"
# RAMCODE_ID comes from strap pins and is not visible on the running board. For another
# module, run once with --with-board and copy the values printed at the end of that run.
BOARDID="${BOARDID:-3767}"
FAB="${FAB:-303}"
BOARDSKU="${BOARDSKU:-0000}"
BOARDREV="${BOARDREV:-F.1}"
CHIP_SKU="${CHIP_SKU:-00:00:00:D3}"
FUSELEVEL="${FUSELEVEL:-fuselevel_production}"
RAMCODE_ID="${RAMCODE_ID:-00:00:00:01}"

WORK_DIR="${WORK_DIR:-$(pwd)}"
force=0
with_board=0
args=("$@")
while [[ $# -gt 0 ]]; do
	case "$1" in
		-w) WORK_DIR="${2:?-w needs a directory}"; shift ;;
		--force) force=1 ;;
		--with-board) with_board=1 ;;
		-h|--help) sed -n '2,19p' "$0"; exit 0 ;;
		*) echo "unknown option: $1" >&2; exit 2 ;;
	esac
	shift
done

mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
IMAGE_DIR="${WORK_DIR}/Linux_for_Tegra/tools/kernel_flash/images"
IMAGE="${IMAGE_DIR}/external/system.img"
LOG="${WORK_DIR}/build-image.log"

if [[ -f "$IMAGE" && "$force" -eq 0 ]]; then
	echo "Flash images are already in ${IMAGE_DIR}."
	echo "Run with --force to generate them again, or write them with:"
	echo "  holybro-flash-image.sh -w ${WORK_DIR}"
	exit 0
fi

if [[ "$with_board" -eq 0 && ( -z "$CHIP_SKU" || -z "$RAMCODE_ID" ) ]]; then
	echo "CHIP_SKU or RAMCODE_ID is not set, so images cannot be generated without the board." >&2
	echo "Run once with the board in REC at 480 Mbps:  $0 -w ${WORK_DIR} --with-board" >&2
	echo "then set the printed values at the top of this script (or as environment variables)." >&2
	exit 1
fi

for f in "$PIN_LIST" "$DEV_SCRIPT"; do
	if [[ ! -f "$f" ]]; then
		echo "Missing ${f}. Keep it next to this script." >&2
		exit 1
	fi
done

if [[ "$(id -u)" -ne 0 ]]; then
	exec sudo WORK_DIR="$WORK_DIR" BOARDID="$BOARDID" FAB="$FAB" BOARDSKU="$BOARDSKU" \
		BOARDREV="$BOARDREV" CHIP_SKU="$CHIP_SKU" FUSELEVEL="$FUSELEVEL" RAMCODE_ID="$RAMCODE_ID" \
		JETSON_USER="$JETSON_USER" JETSON_PASSWORD="$JETSON_PASSWORD" \
		JETSON_HOSTNAME="$JETSON_HOSTNAME" JETSON_TIMEZONE="$JETSON_TIMEZONE" \
		bash "$0" "${args[@]}"
fi

exec > >(tee "$LOG") 2>&1
echo "Work directory: ${WORK_DIR}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wget tar bzip2 lbzip2 libxml2 python3 bc ca-certificates python-is-python3 \
	qemu-user-static binfmt-support

cd "$WORK_DIR"

download() {
	local url="$1"
	local out="$2"
	if [[ -f "$out" ]]; then
		echo "Already downloaded: $out"
		return 0
	fi
	echo "Downloading $out"
	wget -c --show-progress -O "$out" "$url"
}

# chroot into the aarch64 root filesystem through qemu-user-static.
ROOTFS="${WORK_DIR}/Linux_for_Tegra/rootfs"
added_qemu=0

in_rootfs() {
	chroot "$ROOTFS" /usr/bin/env DEBIAN_FRONTEND=noninteractive LC_ALL=C "$@"
}

enter_rootfs() {
	mount -t proc proc "${ROOTFS}/proc"
	mount -t sysfs sys "${ROOTFS}/sys"
	mount --bind /dev "${ROOTFS}/dev"
	mount --bind /dev/pts "${ROOTFS}/dev/pts"
	# Name resolution for apt. The image keeps its own resolv.conf (a systemd-resolved link).
	# A .holybro copy left by an interrupted run is the original, so keep it.
	if [[ -e "${ROOTFS}/etc/resolv.conf.holybro" || -L "${ROOTFS}/etc/resolv.conf.holybro" ]]; then
		rm -f "${ROOTFS}/etc/resolv.conf"
	elif [[ -e "${ROOTFS}/etc/resolv.conf" || -L "${ROOTFS}/etc/resolv.conf" ]]; then
		mv "${ROOTFS}/etc/resolv.conf" "${ROOTFS}/etc/resolv.conf.holybro"
	fi
	if [[ -f /run/systemd/resolve/resolv.conf ]]; then
		cp /run/systemd/resolve/resolv.conf "${ROOTFS}/etc/resolv.conf"
	else
		cp -L /etc/resolv.conf "${ROOTFS}/etc/resolv.conf"
	fi
	# Keep package scripts from starting services inside the chroot.
	printf '#!/bin/sh\nexit 101\n' > "${ROOTFS}/usr/sbin/policy-rc.d"
	chmod +x "${ROOTFS}/usr/sbin/policy-rc.d"
	if [[ ! -e "${ROOTFS}/usr/bin/qemu-aarch64-static" ]]; then
		cp /usr/bin/qemu-aarch64-static "${ROOTFS}/usr/bin/"
		added_qemu=1
	fi
}

leave_rootfs() {
	local m
	for m in dev/pts dev sys proc; do
		if mountpoint -q "${ROOTFS}/${m}"; then
			umount -l "${ROOTFS}/${m}"
		fi
	done
	rm -f "${ROOTFS}/usr/sbin/policy-rc.d"
	if [[ -e "${ROOTFS}/etc/resolv.conf.holybro" || -L "${ROOTFS}/etc/resolv.conf.holybro" ]]; then
		rm -f "${ROOTFS}/etc/resolv.conf"
		mv "${ROOTFS}/etc/resolv.conf.holybro" "${ROOTFS}/etc/resolv.conf"
	fi
	if [[ "$added_qemu" -eq 1 ]]; then
		rm -f "${ROOTFS}/usr/bin/qemu-aarch64-static"
		added_qemu=0
	fi
}

install_jetpack_runtime() {
	local l4t_installed l4t_pinned
	l4t_installed="$(in_rootfs dpkg-query -W -f '${Version}' nvidia-l4t-core)"
	l4t_pinned="$(sed -n 's/^nvidia-l4t-core=//p' "$PIN_LIST")"
	if [[ "$l4t_installed" != "$l4t_pinned" ]]; then
		echo "L4T in the image is ${l4t_installed} but ${PIN_LIST} expects ${l4t_pinned}." >&2
		echo "The BSP and the JetPack version list do not match." >&2
		return 1
	fi

	local source_list="${ROOTFS}/etc/apt/sources.list.d/nvidia-l4t-apt-source.list"
	if [[ ! -f "$source_list" ]]; then
		echo "Missing ${source_list}; apply_binaries.sh did not install the NVIDIA apt source." >&2
		return 1
	fi
	sed -i 's/<SOC>/t234/g' "$source_list"

	# Pin every JetPack package, and keep all other L4T packages at the BSP version.
	# The pins stay in the image so a later apt upgrade does not move the board off this version.
	# apt ignores files in preferences.d unless they have no extension or end in .pref.
	{
		echo "# JetPack ${JETPACK_VERSION} on L4T ${l4t_pinned}, written by holybro-build-image.sh."
		echo "# Delete this file to allow upgrades to a newer JetPack."
		echo
		grep -vE '^(#|$)' "$PIN_LIST" | awk -F= '{print "Package: "$1"\nPin: version "$2"\nPin-Priority: 1001\n"}'
		printf 'Package: nvidia-l4t-*\nPin: version %s\nPin-Priority: 1001\n' "$l4t_pinned"
	} > "${ROOTFS}/etc/apt/preferences.d/jetpack-6.2.2.pref"

	in_rootfs apt-get update
	in_rootfs apt-get install -y "nvidia-jetpack-runtime=${JETPACK_VERSION}"
	in_rootfs apt-get clean
	echo "Installed nvidia-jetpack-runtime $(in_rootfs dpkg-query -W -f '${Version}' nvidia-jetpack-runtime)"
}

# Development packages, the same set as the holybro-dev-env sysroot, through the script
# that is also run by hand on boards flashed earlier.
install_jetpack_dev() {
	cp "$DEV_SCRIPT" "${ROOTFS}/tmp/jetson-install-dev.sh"
	in_rootfs JETPACK_VERSION="$JETPACK_VERSION" bash /tmp/jetson-install-dev.sh
	rm -f "${ROOTFS}/tmp/jetson-install-dev.sh"
	rm -rf "${ROOTFS}/var/lib/apt/lists/"*
}

configure_system() {
	in_rootfs locale-gen en_US.UTF-8
	echo "LANG=en_US.UTF-8" > "${ROOTFS}/etc/default/locale"
	cat > "${ROOTFS}/etc/default/keyboard" <<-'EOF'
		XKBMODEL="pc105"
		XKBLAYOUT="us"
		XKBVARIANT=""
		XKBOPTIONS=""
		BACKSPACE="guess"
	EOF
	if [[ ! -f "${ROOTFS}/usr/share/zoneinfo/${JETSON_TIMEZONE}" ]]; then
		echo "Unknown time zone: ${JETSON_TIMEZONE}" >&2
		return 1
	fi
	ln -sf "/usr/share/zoneinfo/${JETSON_TIMEZONE}" "${ROOTFS}/etc/localtime"
	echo "$JETSON_TIMEZONE" > "${ROOTFS}/etc/timezone"
	echo "Locale en_US.UTF-8, keyboard us, time zone ${JETSON_TIMEZONE}"
}

# USB remote access over the carrier's USB-C (recovery) port. The port has no USB-C role
# controller, so after boot its role stays "none" and the PC never sees the L4T USB device
# (192.168.55.1). usb-role.service sets it to device mode at boot; usb-role turns it on or off.
install_usb_role() {
	cat > "${ROOTFS}/etc/default/usb-role" <<'EOF'
# USB remote access over the USB-C port (usb-role). Change it with: sudo usb-role on|off
ROLE=on
ROLE_SWITCH=usb2-0-role-switch
EOF
	cat > "${ROOTFS}/usr/local/sbin/usb-role" <<'EOF'
#!/bin/bash
# USB remote access over the USB-C port. When on, the PC on that port reaches this board
# at 192.168.55.1 (ssh). The setting is kept in /etc/default/usb-role across reboots.
#   usb-role           show the current state
#   sudo usb-role on   turn USB remote access on (port role device)
#   sudo usb-role off  turn USB remote access off (port role none)
#   usb-role --apply   apply the saved setting (usb-role.service at boot)
set -euo pipefail

CONF=/etc/default/usb-role
ROLE=on
ROLE_SWITCH=usb2-0-role-switch
[[ -f "$CONF" ]] && . "$CONF"
SYSFS="/sys/class/usb_role/${ROLE_SWITCH}/role"

role_for() {
	case "$1" in
		on) echo device ;;
		off) echo none ;;
		*) return 1 ;;
	esac
}

apply() {
	local want i
	want="$(role_for "$1")" || { echo "bad ROLE in $CONF: $1 (use on or off)" >&2; exit 1; }
	# The role switch shows up shortly after the USB driver loads.
	for i in $(seq 1 20); do
		[[ -e "$SYSFS" ]] && break
		sleep 0.5
	done
	[[ -e "$SYSFS" ]] || { echo "$SYSFS not found" >&2; exit 1; }
	echo "$want" > "$SYSFS"
}

show() {
	local cur
	cur="$(cat "$SYSFS" 2>/dev/null || echo missing)"
	if [[ "$cur" == device ]]; then
		echo "USB remote access: on (ssh $(id -un)@192.168.55.1 from the PC on the USB-C port)"
	else
		echo "USB remote access: off (port role ${cur})"
	fi
	echo "saved setting: ${ROLE} (${CONF})"
}

case "${1:-}" in
	"") show ;;
	--apply) apply "$ROLE" ;;
	on|off)
		if [[ "$(id -u)" -ne 0 ]]; then
			echo "Run as root: sudo usb-role $1" >&2
			exit 1
		fi
		if [[ "$1" == off && "${SSH_CONNECTION:-}" == 192.168.55.* ]]; then
			echo "This SSH session runs over USB and will drop. Reconnect over Ethernet."
		fi
		sed -i "s/^ROLE=.*/ROLE=$1/" "$CONF"
		ROLE="$1"
		apply "$ROLE"
		show
		;;
	*)
		echo "usage: usb-role [on|off]" >&2
		exit 2
		;;
esac
EOF
	chmod 755 "${ROOTFS}/usr/local/sbin/usb-role"
	cat > "${ROOTFS}/etc/systemd/system/usb-role.service" <<'EOF'
[Unit]
Description=USB-C port role for USB remote access (usb-role)
Before=nv-l4t-usb-device-mode.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/usb-role --apply

[Install]
WantedBy=multi-user.target
EOF
	mkdir -p "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
	ln -sf /etc/systemd/system/usb-role.service \
		"${ROOTFS}/etc/systemd/system/multi-user.target.wants/usb-role.service"
	echo "USB remote access on by default (usb-role on|off)"
}

create_default_user() {
	if grep -q "^${JETSON_USER}:" "${ROOTFS}/etc/passwd"; then
		# apply_binaries.sh (nv_customize_rootfs.sh) links default.target to nv-oem-config.target
		# again on every run when it is missing, so a rerun brings back the first-boot setup.
		# Redo the bypass that l4t_create_default_user.sh does.
		rm -f "${ROOTFS}/etc/systemd/system/default.target"
		touch "${ROOTFS}/etc/nv/nvautoconfig"
		echo "User ${JETSON_USER} already exists in the image; keeping it and skipping first-boot setup."
		return 0
	fi
	./tools/l4t_create_default_user.sh -u "$JETSON_USER" -p "$JETSON_PASSWORD" \
		-n "$JETSON_HOSTNAME" -a --accept-license
	echo "User ${JETSON_USER}, host name ${JETSON_HOSTNAME}, automatic login"
}

download "$BSP_URL" "$BSP_TBZ"
download "$ROOTFS_URL" "$ROOTFS_TBZ"
download "$PATCH_URL" "$PATCH_TBZ"

if [[ ! -x Linux_for_Tegra/flash.sh ]]; then
	echo "Extracting ${BSP_TBZ}"
	tar xf "$BSP_TBZ"
fi

if [[ ! -d Linux_for_Tegra/rootfs/etc ]]; then
	echo "Extracting root filesystem"
	tar xpf "$ROOTFS_TBZ" -C Linux_for_Tegra/rootfs/
fi

cd Linux_for_Tegra
./tools/l4t_flash_prerequisites.sh
./apply_binaries.sh
tar xf "${WORK_DIR}/${PATCH_TBZ}"

trap leave_rootfs EXIT
enter_rootfs
install_jetpack_runtime
install_jetpack_dev
configure_system
install_usb_role
leave_rootfs
trap - EXIT
create_default_user
if [[ -e "${ROOTFS}/etc/systemd/system/default.target" ]]; then
	echo "First-boot setup (oem-config) is still enabled in the image: ${ROOTFS}/etc/systemd/system/default.target" >&2
	exit 1
fi

if [[ "$force" -eq 1 ]]; then
	rm -rf "$IMAGE_DIR"
fi

if [[ "$with_board" -eq 1 ]]; then
	apx_speed=""
	for vendor in /sys/bus/usb/devices/*/idVendor; do
		[[ -f "$vendor" ]] || continue
		[[ "$(cat "$vendor")" == "0955" ]] || continue
		dir="$(dirname "$vendor")"
		prod="$(cat "${dir}/idProduct")"
		case "$prod" in
			7323|7423|7523|7623)
				apx_speed="$(cat "${dir}/speed")"
				echo "Found NVIDIA APX 0955:${prod} at $(basename "$dir") speed=${apx_speed}"
				break
				;;
		esac
	done
	if [[ "$apx_speed" != "480" ]]; then
		echo "--with-board needs the board in REC at 480 Mbps. Connect it and run again." >&2
		lsusb -t || true
		exit 1
	fi
	echo 2048 > /sys/module/usbcore/parameters/usbfs_memory_mb
	echo -1 > /sys/module/usbcore/parameters/autosuspend
else
	# flash.sh takes RAMCODE as a decimal number made from the RAMCODE_ID bits.
	# RAMCODE_ID must not reach flash.sh: it wins over RAMCODE and is passed on as is,
	# and tegraflash then fails on int('00:00:00:01').
	RAMCODE="$(echo "ibase=2; ${RAMCODE_ID//:/}" | bc)"
	echo "Generating without the board: BOARDID=${BOARDID} FAB=${FAB} BOARDSKU=${BOARDSKU}" \
		"BOARDREV=${BOARDREV} CHIP_SKU=${CHIP_SKU} FUSELEVEL=${FUSELEVEL}" \
		"RAMCODE_ID=${RAMCODE_ID} RAMCODE=${RAMCODE}"
	unset RAMCODE_ID
	export BOARDID FAB BOARDSKU BOARDREV CHIP_SKU FUSELEVEL RAMCODE
fi

./tools/kernel_flash/l4t_initrd_flash.sh \
	--no-flash \
	--external-device nvme0n1p1 \
	-c tools/kernel_flash/flash_l4t_t234_nvme.xml \
	-p "-c bootloader/generic/cfg/flash_t234_qspi.xml" \
	--showlogs \
	--network usb0 \
	"$TARGET" \
	internal

if [[ ! -f "$IMAGE" ]]; then
	echo "Image generation finished but ${IMAGE} is missing. Check ${LOG}." >&2
	exit 1
fi

if [[ "$with_board" -eq 1 ]]; then
	echo
	# The board read leaves cvm.bin (EEPROM) and chip_info.bin_bak (chip) in bootloader/.
	echo "Board identity read during this run. Put RAMCODE_ID (and any value that differs) at the top of this script:"
	cd bootloader
	if [[ -f cvm.bin && -f chip_info.bin_bak ]]; then
		echo "  BOARDID=$(./chkbdinfo -i cvm.bin)"
		echo "  FAB=$(./chkbdinfo -f cvm.bin)"
		echo "  BOARDSKU=$(./chkbdinfo -k cvm.bin)"
		echo "  BOARDREV=$(./chkbdinfo -r cvm.bin)"
		echo "  CHIP_SKU=$(./chkbdinfo -C chip_info.bin_bak)"
		echo "  RAMCODE_ID=$(./chkbdinfo -R chip_info.bin_bak)"
	else
		echo "  cvm.bin or chip_info.bin_bak is missing in $(pwd). Check ${LOG}." >&2
	fi
fi

echo
echo "Images are ready. Turn the board off, put it in REC, power it on until lsusb -t shows 480 Mbps, then run:"
echo "  holybro-flash-image.sh -w ${WORK_DIR}"
