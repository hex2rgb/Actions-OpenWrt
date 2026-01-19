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
TZ="Asia/Shanghai"

# Local paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${HOME}/openwrt-build"

# Step 1: Initialization environment
echo "Step 1: Initialization environment"
export DEBIAN_FRONTEND=noninteractive

sudo rm -rf /etc/apt/sources.list.d/* /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL /usr/local/share/boost /opt/hostedtoolcache/go /opt/hostedtoolcache/Python 2>/dev/null || true
sudo docker image prune --all --force 2>/dev/null || true
sudo -E apt-get -qq update
sudo -E apt-get -qq install ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential bzip2 ccache cmake cpio curl device-tree-compiler fastjar flex gawk gettext git gperf haveged help2man intltool libelf-dev libfuse-dev libglib2.0-dev libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libpython3-dev libreadline-dev libssl-dev libtool lrzsz mkisofs msmtp ninja-build p7zip p7zip-full patch pkgconf python2.7 python3 python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools subversion swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev
sudo -E apt-get -qq install -y gcc-multilib g++-multilib libc6-dev-i386 2>/dev/null || echo "Warning: multilib packages not available, continuing..."
sudo -E apt-get -qq autoremove --purge
sudo -E apt-get -qq clean
sudo timedatectl set-timezone "$TZ"
sudo mkdir -p "$WORK_DIR"
sudo chown $USER:$(id -gn) "$WORK_DIR"

# Step 2: Clone source code
echo "Step 2: Clone source code"
cd "$WORK_DIR"
df -hT $PWD
[ -d "openwrt" ] && rm -rf openwrt
git clone --depth 1 $REPO_URL -b $REPO_TAG openwrt

# Step 3: Load custom feeds
echo "Step 3: Load custom feeds"
[ -e "$SCRIPT_DIR/$FEEDS_CONF" ] && cp "$SCRIPT_DIR/$FEEDS_CONF" "$WORK_DIR/openwrt/feeds.conf.default"
chmod +x "$SCRIPT_DIR/$DIY_P1_SH"
cd "$WORK_DIR/openwrt"
"$SCRIPT_DIR/$DIY_P1_SH"

# Step 4: Update feeds
echo "Step 4: Update feeds"
cd "$WORK_DIR/openwrt"
./scripts/feeds update -a

# Step 5: Install feeds
echo "Step 5: Install feeds"
cd "$WORK_DIR/openwrt"
./scripts/feeds install -a

# Step 6: Load custom configuration
echo "Step 6: Load custom configuration"
[ -e "$SCRIPT_DIR/files" ] && cp -r "$SCRIPT_DIR/files" "$WORK_DIR/openwrt/files"
[ -e "$SCRIPT_DIR/$CONFIG_FILE" ] && cp "$SCRIPT_DIR/$CONFIG_FILE" "$WORK_DIR/openwrt/.config"
chmod +x "$SCRIPT_DIR/$DIY_P2_SH"
cd "$WORK_DIR/openwrt"
"$SCRIPT_DIR/$DIY_P2_SH"

# Step 7: Download package
echo "Step 7: Download package"
cd "$WORK_DIR/openwrt"
make defconfig
make download -j8
find dl -size -1024c -exec ls -l {} \;
find dl -size -1024c -exec rm -f {} \;
df -hT
du -sh dl staging_dir build_dir tmp 2>/dev/null || true
rm -rf .git
find . -type d -name ".git" -exec rm -rf {} + 2>/dev/null || true

# Step 8: Compile the firmware
echo "Step 8: Compile the firmware"
cd "$WORK_DIR/openwrt"
df -hT
rm -rf tmp/info/.packageinfo* tmp/.config* tmp/info/.files-packageinfo* 2>/dev/null || true
echo -e "$(nproc) thread compile"
make -j$(nproc) || make -j1 || make -j1 V=s
grep '^CONFIG_TARGET.*DEVICE.*=y' .config | sed -r 's/.*DEVICE_(.*)=y/\1/' > DEVICE_NAME
[ -s DEVICE_NAME ] && DEVICE_NAME="_$(cat DEVICE_NAME)" || DEVICE_NAME=""
FILE_DATE="_$(date +"%Y%m%d%H%M")"

# Step 9: Check space usage
echo "Step 9: Check space usage"
df -hT

# Step 10: Organize files
echo "Step 10: Organize files"
cd "$WORK_DIR/openwrt/bin/targets"/*/*
rm -rf packages
FIRMWARE="$PWD"

echo "=========================================="
echo "Build completed successfully!"
echo "Firmware location: $FIRMWARE"
echo "=========================================="
