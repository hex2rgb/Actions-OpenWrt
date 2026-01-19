#!/bin/bash
#
# Local OpenWrt Build Script
# Based on GitHub Actions workflow: .github/workflows/openwrt-builder.yml
# For Ubuntu 22.04
#
# Usage: ./build-local.sh

set -e

# Environment variables (from GitHub Actions workflow)
REPO_URL="https://github.com/coolsnowwolf/lede"
REPO_TAG="20230609"
FEEDS_CONF="feeds.conf.default"
CONFIG_FILE=".config"
DIY_P1_SH="diy-part1.sh"
DIY_P2_SH="diy-part2.sh"
UPLOAD_BIN_DIR="false"
UPLOAD_FIRMWARE="true"
TZ="Asia/Shanghai"

# Local paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${HOME}/openwrt-build"
BUILD_DIR="${WORK_DIR}/openwrt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    print_error "Please do not run as root"
    exit 1
fi

# Step 1: Initialization environment
print_info "Step 1: Initialization environment"
export DEBIAN_FRONTEND=noninteractive

print_info "Updating package lists..."
sudo -E apt-get -qq update

print_info "Installing essential dependencies..."
# Install essential packages first (these should always be available)
sudo -E apt-get -qq install -y \
    ack antlr3 asciidoc autoconf automake autopoint binutils bison \
    build-essential bzip2 ccache cmake cpio curl device-tree-compiler \
    fastjar flex gawk gettext git gperf \
    haveged help2man intltool libelf-dev libfuse-dev \
    libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev \
    libncurses5-dev libncursesw5-dev libpython3-dev libreadline-dev \
    libssl-dev libtool lrzsz mkisofs msmtp ninja-build p7zip p7zip-full \
    patch pkgconf python2.7 python3 python3-pyelftools python3-setuptools \
    qemu-utils rsync scons squashfs-tools subversion swig texinfo \
    uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev

# Try to install multilib packages (may not be available in Ubuntu 22.04)
print_info "Attempting to install multilib packages (optional)..."
sudo -E apt-get -qq install -y gcc-multilib g++-multilib libc6-dev-i386 2>/dev/null || \
    print_warn "Multilib packages not available, continuing without them (OpenWrt will build its own toolchain)"

sudo -E apt-get -qq autoremove --purge 2>/dev/null || true
sudo -E apt-get -qq clean

print_info "Setting timezone to ${TZ}..."
sudo timedatectl set-timezone "${TZ}" 2>/dev/null || print_warn "Could not set timezone (may require sudo)"

print_info "Creating work directory: ${WORK_DIR}"
mkdir -p "${WORK_DIR}"

# Step 2: Clone source code
print_info "Step 2: Clone source code"
cd "${WORK_DIR}"
df -hT "${PWD}"

if [ -d "openwrt" ]; then
    print_warn "OpenWrt directory exists, updating to tag ${REPO_TAG}..."
    cd openwrt
    git fetch --tags origin 2>/dev/null || git fetch origin
    if git rev-parse --verify "${REPO_TAG}" >/dev/null 2>&1; then
        git checkout "${REPO_TAG}"
        git clean -fd
    else
        print_warn "Tag ${REPO_TAG} not found, trying as branch..."
        git fetch origin "${REPO_TAG}:${REPO_TAG}" 2>/dev/null || true
        git checkout "${REPO_TAG}" 2>/dev/null || {
            print_error "Tag/branch ${REPO_TAG} not found!"
            exit 1
        }
    fi
    cd ..
else
    print_info "Cloning ${REPO_URL} (tag: ${REPO_TAG})..."
    git clone --depth 1 "${REPO_URL}" -b "${REPO_TAG}" openwrt || {
        print_warn "Failed to clone with tag, trying full clone..."
        git clone "${REPO_URL}" openwrt
        cd openwrt
        git checkout "${REPO_TAG}" || git checkout "origin/${REPO_TAG}"
        cd ..
    }
fi

# Step 3: Load custom feeds
print_info "Step 3: Load custom feeds"
if [ -e "${SCRIPT_DIR}/${FEEDS_CONF}" ]; then
    print_info "Copying ${FEEDS_CONF}..."
    cp "${SCRIPT_DIR}/${FEEDS_CONF}" "${BUILD_DIR}/feeds.conf.default"
fi

if [ -f "${SCRIPT_DIR}/${DIY_P1_SH}" ]; then
    print_info "Running ${DIY_P1_SH}..."
    chmod +x "${SCRIPT_DIR}/${DIY_P1_SH}"
    cd "${BUILD_DIR}"
    "${SCRIPT_DIR}/${DIY_P1_SH}"
else
    cd "${BUILD_DIR}"
fi

# Step 4: Update feeds
print_info "Step 4: Update feeds"
cd "${BUILD_DIR}"
./scripts/feeds update -a

# Step 5: Install feeds
print_info "Step 5: Install feeds"
cd "${BUILD_DIR}"
./scripts/feeds install -a

# Step 6: Load custom configuration
print_info "Step 6: Load custom configuration"
if [ -e "${SCRIPT_DIR}/files" ]; then
    print_info "Copying files directory..."
    cp -r "${SCRIPT_DIR}/files" "${BUILD_DIR}/files"
fi

if [ -e "${SCRIPT_DIR}/${CONFIG_FILE}" ]; then
    print_info "Copying ${CONFIG_FILE}..."
    cp "${SCRIPT_DIR}/${CONFIG_FILE}" "${BUILD_DIR}/.config"
fi

if [ -f "${SCRIPT_DIR}/${DIY_P2_SH}" ]; then
    print_info "Running ${DIY_P2_SH}..."
    chmod +x "${SCRIPT_DIR}/${DIY_P2_SH}"
    cd "${BUILD_DIR}"
    "${SCRIPT_DIR}/${DIY_P2_SH}"
fi

# Step 7: Download package
print_info "Step 7: Download package"
cd "${BUILD_DIR}"
make defconfig
make download -j8

print_info "Checking for failed downloads..."
find dl -size -1024c -exec ls -l {} \; 2>/dev/null || true
find dl -size -1024c -exec rm -f {} \; 2>/dev/null || true

print_info "Disk usage:"
df -hT
du -sh dl staging_dir build_dir tmp 2>/dev/null || true

print_info "Cleaning git files..."
rm -rf .git
find . -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true

# Step 8: Compile the firmware
print_info "Step 8: Compile the firmware"
cd "${BUILD_DIR}"
df -hT

print_info "Cleaning temporary config files..."
rm -rf tmp/info/.packageinfo* tmp/.config* tmp/info/.files-packageinfo* 2>/dev/null || true

print_info "Starting compilation with $(nproc) threads..."
if make -j$(nproc) || make -j1 || make -j1 V=s; then
    print_info "Compilation completed successfully!"
    
    # Extract device name (from workflow)
    if grep -q '^CONFIG_TARGET.*DEVICE.*=y' .config; then
        DEVICE_NAME=$(grep '^CONFIG_TARGET.*DEVICE.*=y' .config | sed -r 's/.*DEVICE_(.*)=y/\1/')
        print_info "Device name: ${DEVICE_NAME}"
    fi
    
    FILE_DATE=$(date +"%Y%m%d%H%M")
    print_info "Build date: ${FILE_DATE}"
else
    print_error "Compilation failed!"
    exit 1
fi

# Step 9: Check space usage
print_info "Step 9: Check space usage"
df -hT

# Step 10: Organize files (if UPLOAD_FIRMWARE is true)
if [ "${UPLOAD_FIRMWARE}" == "true" ]; then
    print_info "Step 10: Organize files"
    cd "${BUILD_DIR}/bin/targets"/*/*
    print_info "Removing packages directory..."
    rm -rf packages
    FIRMWARE="${PWD}"
    print_info "Firmware directory: ${FIRMWARE}"
    
    print_info "Firmware files:"
    ls -lh "${FIRMWARE}"/*.bin "${FIRMWARE}"/*.img 2>/dev/null || true
fi

# Summary
print_info "=========================================="
print_info "Build Summary:"
print_info "=========================================="
print_info "Work directory: ${WORK_DIR}"
print_info "Build directory: ${BUILD_DIR}"
if [ -n "${DEVICE_NAME}" ]; then
    print_info "Device: ${DEVICE_NAME}"
fi
print_info "Build date: ${FILE_DATE}"
if [ -n "${FIRMWARE}" ]; then
    print_info "Firmware location: ${FIRMWARE}"
fi
print_info "=========================================="
print_info "Build process completed successfully!"
