#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Usage: ./build.sh [all|linux|windows|android]
# Pure freestanding C, so neither a platform SDK nor Godot-cpp is needed.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p bin build
touch build/.gdignore
# Never truncate an inode that a running editor/process may have mapped.
# Compile all requested artifacts first, then atomically rename each completed
# library on this same filesystem. A failed build publishes none of its files.
stage="$(mktemp -d build/stage.XXXXXXXX)"
trap 'rm -rf "$stage"' EXIT
artifacts=()
if [[ -n "${SOURCE_WATER_LLVM_ROOT:-}" ]]; then
    export LD_LIBRARY_PATH="$SOURCE_WATER_LLVM_ROOT/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export PATH="$SOURCE_WATER_LLVM_ROOT/lib/llvm-19/bin:$PATH"
    CLANG="${CLANG:-$SOURCE_WATER_LLVM_ROOT/bin/clang-19}"
fi
CLANG="${CLANG:-clang}"
flags=(-std=c11 -O3 -Wall -Wextra -Werror -ffreestanding -fno-builtin
       -fno-stack-protector -fno-ident -fvisibility=hidden
       -fno-fast-math -ffp-contract=off -fno-unwind-tables -fno-asynchronous-unwind-tables)
target="${1:-all}"
case "$target" in all|linux|windows|android) ;; *) echo "Unknown target: $target" >&2; exit 2;; esac
if [[ "$target" == all || "$target" == linux ]]; then
    "$CLANG" "${flags[@]}" --target=x86_64-linux-gnu -fPIC -shared -nostdlib -fuse-ld=lld \
        -Wl,--no-undefined -Wl,-z,relro,-z,now -Wl,--build-id=none \
        source_water.c -o "$stage/libsource_water.linux.x86_64.so"
    artifacts+=(libsource_water.linux.x86_64.so)
fi
if [[ "$target" == all || "$target" == windows ]]; then
    "$CLANG" "${flags[@]}" --target=x86_64-pc-windows-msvc -c source_water.c -o build/source_water.windows.obj
    "${LLD_LINK:-lld-link}" /dll /noentry /nodefaultlib /machine:x64 /timestamp:0 \
        "/out:$stage/source_water.windows.x86_64.dll" /implib:build/source_water.windows.x86_64.lib build/source_water.windows.obj
    artifacts+=(source_water.windows.x86_64.dll)
fi
if [[ "$target" == all || "$target" == android ]]; then
    "$CLANG" "${flags[@]}" --target=aarch64-linux-android24 -fPIC -c source_water.c -o build/source_water.android.o
    "${LD_LLD:-ld.lld}" -shared --no-undefined --build-id=none \
        -z relro -z now -z max-page-size=16384 \
        -soname libsource_water.android.arm64.so \
        build/source_water.android.o -o "$stage/libsource_water.android.arm64.so"
    artifacts+=(libsource_water.android.arm64.so)
fi
for artifact in "${artifacts[@]}"; do mv -f -- "$stage/$artifact" "bin/$artifact"; done
echo "Built source water readback: $target"
