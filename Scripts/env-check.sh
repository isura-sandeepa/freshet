#!/bin/bash
# Prints the toolchain details the build depends on.
echo "== macOS"; sw_vers
echo "== Xcode / Swift"
xcode-select -p
xcodebuild -version 2>/dev/null || echo "xcodebuild unavailable (Command Line Tools only)"
swift --version
clang --version | head -1
echo "== Homebrew"; brew --version | head -1; brew list --versions boost openssl@3
echo "== Boost headers"
for d in /opt/homebrew/opt/boost/include /opt/homebrew/include; do
  if [ -f "$d/boost/version.hpp" ]; then
    echo "$d -> $(cd "$d" && pwd -P): $(grep -m1 'define BOOST_LIB_VERSION' "$d/boost/version.hpp")"
  else
    echo "$d: no boost/version.hpp"
  fi
done
echo "== OpenSSL"
P=/opt/homebrew/opt/openssl@3
echo "$P -> $(cd "$P" 2>/dev/null && pwd -P)"
"$P/bin/openssl" version 2>&1
ls -l "$P"/lib/libssl.* "$P"/lib/libcrypto.* 2>&1
echo "== Vendored libtorrent"
grep -m1 'define LIBTORRENT_VERSION ' Vendor/libtorrent/include/libtorrent/version.hpp 2>&1
echo "$(find Vendor/libtorrent -name '*.cpp' 2>/dev/null | wc -l | tr -d ' ') source files"
echo "== Network"
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1
/usr/libexec/ApplicationFirewall/socketfilterfw --getblockall 2>&1
echo "-- sockets on the default BitTorrent ports"
lsof -nP -iTCP:6881-6891 -iUDP:6881-6891 2>&1 | head -40
echo "== Git"
command -v git && git --version
command -v gh && gh --version | head -1 && gh auth status 2>&1 | grep -E 'Logged in|account' | head -2
git config --global user.name; git config --global user.email
