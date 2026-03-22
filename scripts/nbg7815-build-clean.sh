#!/usr/bin/env bash
set -euo pipefail

TOPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JOBS="${JOBS:-$(nproc)}"
FEEDS_UPDATE="${FEEDS_UPDATE:-1}"
DL_PARALLEL="${DL_PARALLEL:-8}"
FEED_RETRIES="${FEED_RETRIES:-3}"
REQUIRED_FEEDS="${REQUIRED_FEEDS:-packages luci routing telephony nss_packages sqm_scripts_nss video}"
NBG7815_EXPECT_BRANCH="${NBG7815_EXPECT_BRANCH:-nbg7815-v25.12.0-patched}"
SKIP_BRANCH_CHECK="${SKIP_BRANCH_CHECK:-0}"

echo "TOPDIR: $TOPDIR"
echo "JOBS: $JOBS"
echo "FEED_RETRIES: $FEED_RETRIES"
echo "REQUIRED_FEEDS: $REQUIRED_FEEDS"

cd "$TOPDIR"

if [ "$SKIP_BRANCH_CHECK" != "1" ] && git rev-parse --git-dir >/dev/null 2>&1; then
	CUR_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
	if [ "$CUR_BRANCH" = "nbg7815-v25.12.0-official" ]; then
		echo "Refusing to build on branch nbg7815-v25.12.0-official (vanilla OpenWrt only, no NBG7815 patches)." >&2
		echo "Checkout nbg7815-v25.12.0-patched or set SKIP_BRANCH_CHECK=1 to override." >&2
		exit 1
	fi
	if [ -n "$NBG7815_EXPECT_BRANCH" ] && [ "$CUR_BRANCH" != "$NBG7815_EXPECT_BRANCH" ] && [ "$CUR_BRANCH" != "unknown" ]; then
		echo "Warning: building on branch '$CUR_BRANCH' (expected '$NBG7815_EXPECT_BRANCH'). Set NBG7815_EXPECT_BRANCH= to silence." >&2
	fi
fi

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

echo "[4/6] Actualizing .config (defconfig + conf --olddefconfig)"
# defconfig: align with in-tree defaults for the selected target (builds scripts/config/conf)
make defconfig
# Merge new Kconfig symbols after feed updates (OpenWrt has no top-level 'make olddefconfig')
./scripts/config/conf --olddefconfig Config.in

echo "[5/6] Downloading sources"
make download -j"$DL_PARALLEL" || {
	echo "Parallel download had failures; retrying with -j1..." >&2
	make download -j1
}

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
echo ""
echo "SHA256:"
sha256sum "$SYSUPGRADE_BIN" "$FACTORY_BIN"
exit 0
