#!/bin/bash
#
# canon-build-packages.sh
#
# Rebuild Canon's legacy CAPT packages for Debian 13 (Trixie).
#
# Run as root from the directory containing:
#   cndrvcups-common_3.21-1_amd64.deb
#   cndrvcups-capt_2.71-1_amd64.deb
#
# Produces:
#   cndrvcups-common_3.21-1_amd64-fixed.deb
#   cndrvcups-capt_2.71-1_amd64-fixed.deb
#
# Only the Debian control metadata is changed; Canon's payload files are
# extracted and rebuilt unchanged.
#

set -euo pipefail

COMMON_IN="cndrvcups-common_3.21-1_amd64.deb"
CAPT_IN="cndrvcups-capt_2.71-1_amd64.deb"

WORK="${PWD}/canon-build"
COMMON_TREE="${WORK}/common"
CAPT_TREE="${WORK}/capt"

COMMON_OUT="${PWD}/cndrvcups-common_3.21-1_amd64-fixed.deb"
CAPT_OUT="${PWD}/cndrvcups-capt_2.71-1_amd64-fixed.deb"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

[[ $EUID -eq 0 ]] || die "Run as root."
[[ -f "$COMMON_IN" ]] || die "Missing $COMMON_IN"
[[ -f "$CAPT_IN" ]] || die "Missing $CAPT_IN"

for cmd in dpkg-deb sed awk grep find; do
    need_cmd "$cmd"
done

echo "==> Checking source packages"
dpkg-deb --info "$COMMON_IN" >/dev/null
dpkg-deb --info "$CAPT_IN" >/dev/null

echo "==> Cleaning build directory"
rm -rf "$WORK"
mkdir -p "$COMMON_TREE" "$CAPT_TREE"

echo "==> Extracting packages"
dpkg-deb -R "$COMMON_IN" "$COMMON_TREE"
dpkg-deb -R "$CAPT_IN" "$CAPT_TREE"

COMMON_CONTROL="$COMMON_TREE/DEBIAN/control"
CAPT_CONTROL="$CAPT_TREE/DEBIAN/control"

[[ -f "$COMMON_CONTROL" ]] || die "Missing $COMMON_CONTROL"
[[ -f "$CAPT_CONTROL" ]] || die "Missing $CAPT_CONTROL"

echo
echo "==> Original common Depends"
grep '^Depends:' "$COMMON_CONTROL" || true

echo
echo "==> Original CAPT Depends"
grep '^Depends:' "$CAPT_CONTROL" || true

#
# cndrvcups-common 3.21-1
#
# Trixie does not provide the old libglade2-0/libgtk2.0-0 dependency names,
# and the old package's CUPS dependency names are obsolete after the Trixie
# t64 transition. The working package retained these runtime dependencies.
#
echo
echo "==> Replacing common package Depends"

awk '
BEGIN { in_depends=0 }
/^Depends:/ {
    in_depends=1
    print "Depends: libc6, libglib2.0-0, libstdc++6, ghostscript"
    next
}
(in_depends && /^[^ \t]/) {
    in_depends=0
}
!in_depends { print }
' "$COMMON_CONTROL" > "$COMMON_CONTROL.new"

mv "$COMMON_CONTROL.new" "$COMMON_CONTROL"

#
# cndrvcups-capt 2.71-1
#
# Trixie uses libatk1.0-0t64. The obsolete libgcc1, libglade2-0 and
# libgtk2.0-0 dependencies are removed. These are the dependencies that
# were used successfully with the rebuilt package.
#
echo "==> Replacing CAPT package Depends"

awk '
BEGIN { in_depends=0 }
/^Depends:/ {
    in_depends=1
    print "Depends: libc6, libatk1.0-0t64, libglib2.0-0, libpopt0, libstdc++6, libxml2, zlib1g, cndrvcups-common"
    next
}
(in_depends && /^[^ \t]/) {
    in_depends=0
}
!in_depends { print }
' "$CAPT_CONTROL" > "$CAPT_CONTROL.new"

mv "$CAPT_CONTROL.new" "$CAPT_CONTROL"

echo
echo "==> Fixed common Depends"
grep '^Depends:' "$COMMON_CONTROL"

echo
echo "==> Fixed CAPT Depends"
grep '^Depends:' "$CAPT_CONTROL"

echo
echo "==> Building common package"
rm -f "$COMMON_OUT"
dpkg-deb --build "$COMMON_TREE" "$COMMON_OUT"

echo "==> Building CAPT package"
rm -f "$CAPT_OUT"
dpkg-deb --build "$CAPT_TREE" "$CAPT_OUT"

echo
echo "==> Verifying rebuilt package metadata"
dpkg-deb --info "$COMMON_OUT" | grep -E '^( Package:| Version:| Architecture:| Depends:)'
echo
dpkg-deb --info "$CAPT_OUT" | grep -E '^( Package:| Version:| Architecture:| Depends:)'

echo
echo "==> Checking important Canon files"
for f in \
    /usr/bin/captfilter \
    /usr/bin/captmon \
    /usr/sbin/ccpd \
    /usr/sbin/ccpdadmin \
    /usr/lib/cups/filter/pstocapt \
    /usr/lib/cups/backend/ccp \
    /usr/share/cups/model/CNCUPSLBP1210CAPTK.ppd
do
    if [[ -e "$COMMON_TREE$f" || -e "$CAPT_TREE$f" ]]; then
        echo "OK      $f"
    else
        echo "WARNING $f not found in rebuilt package trees"
    fi
done

echo
echo "Build complete:"
echo "  $COMMON_OUT"
echo "  $CAPT_OUT"
echo
echo "Install with:"
echo "  apt install ./$COMMON_OUT ./$CAPT_OUT"
