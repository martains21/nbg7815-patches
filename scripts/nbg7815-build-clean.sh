#!/usr/bin/env bash
set -euo pipefail

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="${JOBS:-$(nproc)}"
FEEDS_UPDATE="${FEEDS_UPDATE:-1}"
DL_PARALLEL="${DL_PARALLEL:-8}"
FEED_RETRIES="${FEED_RETRIES:-3}"
REQUIRED_FEEDS="${REQUIRED_FEEDS:-packages luci routing telephony nss_packages sqm_scripts_nss video}"

echo "TOPDIR: $TOPDIR"
echo "JOBS: $JOBS"
echo "FEED_RETRIES: $FEED_RETRIES"
echo "REQUIRED_FEEDS: $REQUIRED_FEEDS"

cd "$TOPDIR"

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run this script with sudo/root. Run as regular user." >&2
  exit 1
fi

if [ "$FEEDS_UPDATE" = "1" ]; then
  echo "[1/6] Updating and installing feeds"
  ./scripts/feeds update -a || true

  for feed in $REQUIRED_FEEDS; do
    ok=0
    for attempt in $(seq 1 "$FEED_RETRIES"); do
      if [ -d "$TOPDIR/feeds/$feed" ]; then
        ok=1
        break
      fi
      echo "Feed '$feed' missing, retry $attempt/$FEED_RETRIES"
      ./scripts/feeds update "$feed" && [ -d "$TOPDIR/feeds/$feed" ] && {
        ok=1
        break
      }
      sleep 2
    done

    if [ "$ok" -ne 1 ]; then
      echo "Required feed '$feed' is unavailable after $FEED_RETRIES retries." >&2
      echo "Check internet access to feed host or set REQUIRED_FEEDS without '$feed'." >&2
      exit 1
    fi
  done

  ./scripts/feeds install -a
else
  echo "[1/6] Skipping feeds update/install (FEEDS_UPDATE=$FEEDS_UPDATE)"
fi

echo "[2/6] Cleaning target artifacts to prevent kernel/kmod ABI mixing"
make target/linux/clean
make package/kernel/linux/clean

echo "[3/6] Removing old target outputs, indexes and target build dirs"
rm -rf "$TOPDIR/tmp" || true
rm -rf "$TOPDIR/bin/targets/qualcommax/ipq807x" || true
rm -rf "$TOPDIR/bin/packages/aarch64_cortex-a53" || true
find "$TOPDIR/staging_dir" -maxdepth 1 -type d -name 'target-*' -exec rm -rf {} + || true
find "$TOPDIR/build_dir" -maxdepth 1 -type d -name 'target-*' -exec rm -rf {} + || true

echo "[4/6] Syncing existing .config with defaults (defconfig)"
make defconfig

echo "[5/6] Downloading sources"
make download -j"$DL_PARALLEL"

echo "[6/6] Building firmware and packages"
if ! make -j"$JOBS" V=s; then
  echo "Build failed (non-zero exit code)" >&2
  exit 1
fi

SYSUPGRADE_BIN="$TOPDIR/bin/targets/qualcommax/ipq807x/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-sysupgrade.bin"
FACTORY_BIN="$TOPDIR/bin/targets/qualcommax/ipq807x/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-factory.bin"

if [ ! -s "$SYSUPGRADE_BIN" ]; then
  echo "Build output check failed: missing or empty $SYSUPGRADE_BIN" >&2
  exit 1
fi

if [ ! -s "$FACTORY_BIN" ]; then
  echo "Build output check failed: missing or empty $FACTORY_BIN" >&2
  exit 1
fi

echo "Build finished successfully"
echo "Artifacts:"
echo "  $SYSUPGRADE_BIN"
echo "  $FACTORY_BIN"
exit 0
