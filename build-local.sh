#!/bin/bash
#
# Local OpenWrt Build Script
# Based on GitHub Actions workflow
# For Ubuntu 22.04
#
# Usage: ./build-local.sh

set -e

# Configuration
REPO_URL="https://github.com/coolsnowwolf/lede"
REPO_TAG="20230609"
FEEDS_CONF="feeds.conf.default"
CONFIG_FILE=".config"
DIY_P1_SH="diy-part1.sh"
DIY_P2_SH="diy-part2.sh"
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
print_info "Initializing environment..."
sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL /usr/local/share/boost /opt/hostedtoolcache/go /opt/hostedtoolcache/Python 2>/dev/null || true
sudo docker image prune --all --force 2>/dev/null || true

print_info "Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get -qq update
sudo -E apt-get -qq install -y \
    ack antlr3 asciidoc autoconf automake autopoint binutils bison \
    build-essential bzip2 ccache cmake cpio curl device-tree-compiler \
    fastjar flex gawk gettext gcc-multilib g++-multilib git gperf \
    haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev \
    libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev \
    libncurses5-dev libncursesw5-dev libpython3-dev libreadline-dev \
    libssl-dev libtool lrzsz mkisofs msmtp ninja-build p7zip p7zip-full \
    patch pkgconf python2.7 python3 python3-pyelftools python3-setuptools \
    qemu-utils rsync scons squashfs-tools subversion swig texinfo \
    uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev

sudo -E apt-get -qq autoremove --purge
sudo -E apt-get -qq clean

# Create work directory
print_info "Creating work directory: ${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# Step 2: Clone source code
if [ -d "openwrt" ]; then
    print_warn "OpenWrt directory exists, updating..."
    cd openwrt
    git fetch --tags origin
    git checkout "${REPO_TAG}"
    cd ..
else
    print_info "Cloning source code..."
    git clone --depth 1 "${REPO_URL}" -b "${REPO_TAG}" openwrt
fi

cd "${BUILD_DIR}"

# Step 3: Load custom feeds
print_info "Loading custom feeds..."
if [ -f "${OLDPWD}/${FEEDS_CONF}" ]; then
    cp "${OLDPWD}/${FEEDS_CONF}" feeds.conf.default
fi

if [ -f "${OLDPWD}/${DIY_P1_SH}" ]; then
    chmod +x "${OLDPWD}/${DIY_P1_SH}"
    "${OLDPWD}/${DIY_P1_SH}"
fi

# Step 4: Update feeds
print_info "Updating feeds..."
./scripts/feeds update -a

# Step 5: Install feeds
print_info "Installing feeds..."
./scripts/feeds install -a

# Step 6: Load custom configuration
print_info "Loading custom configuration..."
if [ -f "${OLDPWD}/${CONFIG_FILE}" ]; then
    cp "${OLDPWD}/${CONFIG_FILE}" .config
fi

if [ -f "${OLDPWD}/${DIY_P2_SH}" ]; then
    chmod +x "${OLDPWD}/${DIY_P2_SH}"
    "${OLDPWD}/${DIY_P2_SH}"
fi

# Step 7: Download packages
print_info "Downloading packages..."
make defconfig
make download -j$(nproc)

# Check for failed downloads
print_info "Checking for failed downloads..."
find dl -size -1024c -exec ls -l {} \; 2>/dev/null || true
find dl -size -1024c -exec rm -f {} \; 2>/dev/null || true

# Show disk usage
print_info "Disk usage:"
df -hT
du -sh dl staging_dir build_dir tmp 2>/dev/null || true

# Clean git to save space
print_info "Cleaning git files..."
rm -rf .git
find . -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true

# Step 8: Compile the firmware
print_info "Compiling firmware..."
print_info "Using $(nproc) threads for compilation"

# Compile with progress
if make -j$(nproc) V=s 2>&1 | tee build.log; then
    print_info "Build completed successfully!"
    
    # Find device name
    if grep -q '^CONFIG_TARGET.*DEVICE.*=y' .config; then
        DEVICE_NAME=$(grep '^CONFIG_TARGET.*DEVICE.*=y' .config | sed -r 's/.*DEVICE_(.*)=y/\1/')
        print_info "Device name: ${DEVICE_NAME}"
    fi
    
    # Show firmware location
    print_info "Firmware location:"
    find bin -name "*.bin" -o -name "*.img" 2>/dev/null | head -10 || true
    
else
    print_error "Build failed! Check build.log for details."
    exit 1
fi

# Final disk usage
print_info "Final disk usage:"
df -hT

print_info "Build process completed!"
print_info "Firmware files are in: ${BUILD_DIR}/bin"
