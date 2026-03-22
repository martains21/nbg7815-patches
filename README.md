# NBG7815 OpenWrt 25.12.0 Patchset

This repository is a personal OpenWrt tree for the Zyxel `NBG7815`.

It exists to keep one reproducible source tree with:
- official OpenWrt `openwrt-25.12` as the base
- NSS acceleration for `ipq807x`
- `NBG7815` device-specific fixes and defaults
- a known-good build and upgrade path from official OpenWrt

This is not a generic OpenWrt fork for all targets. It is a focused `qualcommax/ipq807x -> zyxel_nbg7815` tree with the extra patches needed for this hardware.

## What Is Patched Here

This tree contains four main groups of changes.

### 1. NSS integration

- NSS feeds in `feeds.conf.default`
- `qca-nss-drv`, `qca-nss-ecm`, `qca-nss-clients`, `qca-mcs`, `qca-nss-cfi`
- NSS qdisc, skb recycler, pbuf tuning, Wi-Fi NSS plumbing
- `ath11k_nss` and `mac80211` NSS patchsets

### 2. Zyxel NBG7815 support

- `ipq8074-nbg7815.dts`
- LP5569 LED support and `led-ctl`
- fan control and thermal defaults
- board-specific MAC/caldata handling
- `ipq-wifi-zyxel_nbg7815`

### 3. Storage layout and first-boot behavior

- ROM `fstab` for:
  - `/overlay -> /dev/mmcblk0p10`
  - `/backup -> /dev/mmcblk0p1`
- extroot cleanup in preinit
- first-boot storage migration logic
- cleanup for stale overlay kernel module metadata

### 4. Runtime fixes and polish

- `zram` defaults in ROM:
  - `384 MiB`
  - `lz4`
  - priority `100`
- ROM `system`, `wireless`, and `nbg7815_led` defaults
- board sysctl defaults
- Wi-Fi script fixes for noisy unsupported operations
- `qca-nss-ecm` startup fix
- Aquantia thermal trip clamp fix
- `ath11k` DTS `m3-dump-addr` fix for `NBG7815`
- LP5569 LED state machine with:
  - one active state at a time
  - night mode
  - late first-boot restart handling
  - transient USB notification

## NSS Support Matrix

This matrix describes the current state of the `NBG7815` build in this repository.

- `enabled` means the feature is turned on in the current build
- `validated` means it was checked on the router at runtime
- `implemented` means patch support exists in tree, but it is not enabled in the current build

| Feature | State | Notes |
| --- | --- | --- |
| Bridge | enabled, validated | NSS core path active |
| VLAN | enabled, validated | NSS VLAN manager enabled |
| PPPoE | enabled | Not runtime-tested against a live peer |
| GRE | enabled, validated | Temporary GRE tunnel create/delete works |
| L2TPv2 | enabled, validated | Kernel path and PPP plugin present |
| PPTP | enabled, validated | Kernel path and PPP plugin present |
| TUN6RD | enabled, validated | SIT/6rd tunnel create/delete works |
| TUNIPIP6 | enabled, validated | ip6ip6 tunnel create/delete works |
| WiFi AP/STA offload | enabled, validated | Current ath11k NSS path in use |
| WiFi WDS | implemented | Patch support exists, not validated |
| WiFi AP VLAN | implemented | Patch support exists, not validated |
| WiFi Mesh | implemented, disabled | Patch support exists, feature not enabled |
| Mirror | disabled | Not enabled in current build |
| RMNET | disabled | Not enabled in current build |
| MAP-T | disabled | Not enabled in current build |
| MATCH | disabled | Not enabled in current build |
| VXLAN | disabled | Not enabled in current build |
| IPsec | disabled | Not enabled in current build |
| PVXLAN | disabled | Not enabled in current build |
| CLMAP | disabled | Not enabled in current build |
| TLS | disabled | Not enabled in current build |
| CAPWAP | disabled | Not enabled in current build |
| DTLS | disabled | Not enabled in current build |

## Build Dependencies

Example dependency set for Debian/Ubuntu:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential clang flex bison gawk gettext git file rsync unzip wget curl \
  libncurses-dev libssl-dev zlib1g-dev python3 python3-distutils python3-setuptools \
  patch tar xz-utils perl grep sed g++ gcc make
```

If your distro uses different package names, install the equivalent toolchain, build tools, Python 3 tooling, compression tools, and OpenSSL/ncurses development headers.

## Build

From a clean checkout:

```bash
cd /path/to/nbg7815-patches
./scripts/feeds update -a
./scripts/feeds install -a
make defconfig
make -j"$(nproc)" V=s
```

## Flash

This tree is intended to be flashed from an existing official OpenWrt installation on `NBG7815`.

Copy the new image to the router:

```bash
scp -O bin/targets/qualcommax/ipq807x/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-sysupgrade.bin root@192.168.1.1:/tmp/
```

On the router:

```sh
sha256sum /tmp/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-sysupgrade.bin
sysupgrade -T /tmp/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-sysupgrade.bin
sysupgrade -b /tmp/nbg7815-backup.tar.gz
sysupgrade -n /tmp/openwrt-qualcommax-ipq807x-zyxel_nbg7815-squashfs-sysupgrade.bin
```

Use `-n` deliberately: this tree has custom NSS, storage, and board-specific behavior, so carrying old overlay data forward is more likely to break things than help.

## Verify

After first boot, verify the basics.

### Storage

```sh
df -h
mount | grep -E 'overlay|backup'
cat /etc/config/fstab
```

Expected:
- `/overlay` on `/dev/mmcblk0p10`
- `/backup` on `/dev/mmcblk0p1`

### ZRAM

```sh
swapon -s
cat /etc/config/system
```

Expected:
- `/dev/zram0`
- about `393212` KiB
- `lz4`
- priority `100`

### NSS

```sh
lsmod | grep qca
dmesg | grep -i nss
logread | grep -iE 'nss|ecm|qca-nss'
```

Expected:
- NSS cores boot successfully
- ECM initializes
- no `nf_conntrack_events` startup warning
- if tunnel features are enabled, related NSS modules load cleanly

### NSS Tunnel Features

```sh
lsmod | grep -E 'qca_nss|pptp|l2tp|gre|sit'
find /usr/lib/pppd -type f | grep -E 'pptp|l2tp|pppol2tp'
ip link show type gre
```

Expected:
- `qca_nss_gre`, `qca_nss_l2tpv2`, `qca_nss_pptp`, `qca_nss_tun6rd`, `qca_nss_tunipip6` loaded
- `pppol2tp.so` and `pptp.so` present
- base tunnel devices such as `gre0` and `sit0` present

### Wi-Fi

```sh
iw dev
wifi status
logread | grep -iE 'ath11k|hostapd|wpa_supplicant'
```

Expected:
- radios present
- no `command failed: Not supported (-95)`
- no `UUID mismatch`
- no `squashfs image failed sanity check`

### Hardware

```sh
ls /sys/class/leds
nbg7815-led-state status
ps | grep fanctld
for f in /sys/class/thermal/thermal_zone*/temp; do echo "$f: $(cat $f)"; done
```

Expected:
- LED devices present
- `nbg7815-led-state status` shows the selected state and reasons
- `fanctld` running
- thermal zones readable

### LED

```sh
nbg7815-led-state help
nbg7815-led-state status
nbg7815-led-state apply
nbg7815-led-state set wps
sleep 3
nbg7815-led-state clear wps
```

Expected:
- `apply` returns the LED to the currently computed state
- `status` shows which state won and why
- temporary states such as `wps` override the normal matrix and then clear cleanly

## Notes

- `psci: [Firmware Bug]: failed to set PC mode: -1` is a firmware / boot chain message, not a tree-specific regression.
- `ath11k` may still print benign firmware-level warnings depending on firmware behavior, but the known noisy boot issues fixed in this tree should stay gone.

In one sentence:

> This repository is a working OpenWrt 25.12.0 + NSS + Zyxel NBG7815 patch tree with storage, Wi-Fi, LED, fan, and first-boot fixes for building reproducible firmware on top of official OpenWrt.

## Credits

This tree was built with help from upstream and community work, especially:

- OpenWrt
- `qosmio/25.12-nss`
- `asvio/nbg7815-nss`
