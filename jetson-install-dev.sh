#!/bin/bash
# Install the JetPack 6.2.2 development packages on a Jetson made with holybro-build-image.sh,
# so the board has the same libraries and headers as the holybro-dev-env sysroot
# (nvidia-jetpack-dev: CUDA compiler nvcc and headers, OpenCV 4.8, TensorRT, cuDNN, VPI)
# plus native build tools (gcc, g++, make, cmake, pkg-config).
#
# holybro-build-image.sh runs this inside the image, so a freshly flashed board already has it.
# On a board flashed before that, run it once on the board (internet needed, about 5 GB):
#   sudo bash jetson-install-dev.sh
#
# Versions come from the pins the image already has (/etc/apt/preferences.d/jetpack-6.2.2.pref),
# so apt never installs JetPack 6.2.3 packages. The NVIDIA OpenCV 4.8 headers replace the partial
# Ubuntu OpenCV 4.5.4 headers that come with the NVIDIA sample root file system.

set -euo pipefail

JETPACK_VERSION="${JETPACK_VERSION:-6.2.2+b24}"
PIN_FILE=/etc/apt/preferences.d/jetpack-6.2.2.pref

if [[ "$(id -u)" -ne 0 ]]; then
	echo "Run as root: sudo bash $0" >&2
	exit 1
fi

runtime="$(dpkg-query -W -f '${Version}' nvidia-jetpack-runtime 2>/dev/null || true)"
if [[ "$runtime" != "$JETPACK_VERSION" || ! -f "$PIN_FILE" ]]; then
	echo "This system does not have the JetPack ${JETPACK_VERSION} runtime and pins from holybro-build-image.sh" >&2
	echo "(nvidia-jetpack-runtime: ${runtime:-not installed}, ${PIN_FILE}: $([[ -f $PIN_FILE ]] && echo present || echo missing))." >&2
	exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y "nvidia-jetpack-dev=${JETPACK_VERSION}" build-essential cmake pkg-config
apt-get clean

# nvcc lives in /usr/local/cuda/bin, which is not on the default PATH.
cat > /etc/profile.d/cuda.sh <<'EOF'
# CUDA tools (nvcc) and libraries, written by jetson-install-dev.sh.
case ":$PATH:" in *:/usr/local/cuda/bin:*) ;; *) PATH="/usr/local/cuda/bin:$PATH" ;; esac
export PATH
EOF

echo "Installed nvidia-jetpack-dev $(dpkg-query -W -f '${Version}' nvidia-jetpack-dev)"
echo "  nvcc   $(/usr/local/cuda/bin/nvcc --version | sed -n 's/.*release \([^,]*\).*/\1/p')"
echo "  OpenCV $(pkg-config --modversion opencv4)"
echo "  cmake  $(cmake --version | sed -n '1s/cmake version //p'), gcc $(gcc -dumpversion)"
echo "Open a new shell (or log in again) so nvcc is on PATH."
