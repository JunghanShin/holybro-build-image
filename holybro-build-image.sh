#!/bin/bash
# Build a Holybro Pixhawk Jetson baseboard image for Jetson Orin NX.
# JetPack 6.2.2 (L4T r36.5) uses the target name jetson-orin-nano-devkit-super.
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

TARGET="jetson-orin-nano-devkit-super"
BSP_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/release/Jetson_Linux_r36.5.0_aarch64.tbz2"
ROOTFS_URL="https://developer.nvidia.com/downloads/embedded/l4t/r36_release_v5.0/release/Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2"
PATCH_URL="https://2367252986-files.gitbook.io/~/files/v0/b/gitbook-x-prod.appspot.com/o/spaces%2FLIgtGDAvVGkCKGOJb1bR%2Fuploads%2FJRxHWde4kntHcgKoUTmO%2Fholybro_jp622.tbz2?alt=media&token=cab3e1cd-d017-43bc-bbfd-1c4650bb03cc"
BSP_TBZ="Jetson_Linux_r36.5.0_aarch64.tbz2"
ROOTFS_TBZ="Tegra_Linux_Sample-Root-Filesystem_r36.5.0_aarch64.tbz2"
PATCH_TBZ="holybro_jp622.tbz2"

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
		-h|--help) sed -n '2,17p' "$0"; exit 0 ;;
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

if [[ "$(id -u)" -ne 0 ]]; then
	exec sudo WORK_DIR="$WORK_DIR" BOARDID="$BOARDID" FAB="$FAB" BOARDSKU="$BOARDSKU" \
		BOARDREV="$BOARDREV" CHIP_SKU="$CHIP_SKU" FUSELEVEL="$FUSELEVEL" RAMCODE_ID="$RAMCODE_ID" \
		bash "$0" "${args[@]}"
fi

exec > >(tee "$LOG") 2>&1
echo "Work directory: ${WORK_DIR}"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y wget tar bzip2 lbzip2 libxml2 python3 bc ca-certificates python-is-python3

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
	RAMCODE="$(echo "ibase=2; ${RAMCODE_ID//:/}" | bc)"
	echo "Generating without the board: BOARDID=${BOARDID} FAB=${FAB} BOARDSKU=${BOARDSKU}" \
		"BOARDREV=${BOARDREV} CHIP_SKU=${CHIP_SKU} FUSELEVEL=${FUSELEVEL}" \
		"RAMCODE_ID=${RAMCODE_ID} RAMCODE=${RAMCODE}"
	export BOARDID FAB BOARDSKU BOARDREV CHIP_SKU FUSELEVEL RAMCODE_ID RAMCODE
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
