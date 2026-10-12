#!/usr/bin/env bash
# Entry point for the Linux build containers. Configures out-of-tree so the
# host's macOS build directory is never reused, and writes binaries to a
# platform-named folder under ./binaries. The C++ runtime is linked statically
# by default, matching the release build: these artifacts are the ones the
# stock-distribution checks run, and they must not need the container's GCC
# runtime installed on the target.
set -euo pipefail

PLATFORM="${WEAKLINK_PLATFORM:-linux-$(uname -m)}"
BUILD_DIR="build/${PLATFORM}"
BIN_DIR="/src/binaries/${PLATFORM}"

cmake -S /src -B "/src/${BUILD_DIR}" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DWEAKLINK_BUILD_TESTS="${WEAKLINK_BUILD_TESTS:-ON}" \
  -DWEAKLINK_STATIC_RUNTIME="${WEAKLINK_STATIC_RUNTIME:-ON}" \
  -DWEAKLINK_BIN_DIR="${BIN_DIR}"

cmake --build "/src/${BUILD_DIR}" -j "$(nproc)"

if [[ "${WEAKLINK_BUILD_TESTS:-ON}" == "ON" ]]; then
  ctest --test-dir "/src/${BUILD_DIR}" --output-on-failure
fi

echo "binaries -> ${BIN_DIR}"
ls -la "${BIN_DIR}"
