#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

uname_os=$(uname -s)
uname_arch=$(uname -m)

case "$uname_os" in
  Darwin) os="macos" ;;
  Linux) os="linux" ;;
  *)
    printf '不支持的操作系统: %s\n' "$uname_os" >&2
    exit 1
    ;;
esac

case "$uname_arch" in
  arm64|aarch64) arch="arm64" ;;
  x86_64|amd64) arch="x64" ;;
  *)
    printf '不支持的 CPU 架构: %s\n' "$uname_arch" >&2
    exit 1
    ;;
esac

binary_name="vtt-to-lrc-$os-$arch"
SOURCE_BIN="$ROOT_DIR/rust-cli/target/release/vtt-to-lrc-rust"
ASSET_BIN="$ROOT_DIR/assets/backend/$binary_name"
SKILL_BIN="$ROOT_DIR/skill-package/vtt-to-lrc/scripts/$binary_name"

cargo build --release --manifest-path "$ROOT_DIR/rust-cli/Cargo.toml"
mkdir -p "$(dirname "$ASSET_BIN")" "$(dirname "$SKILL_BIN")"
cp "$SOURCE_BIN" "$ASSET_BIN"
chmod +x "$ASSET_BIN"
cp "$SOURCE_BIN" "$SKILL_BIN"
chmod +x "$SKILL_BIN"

printf '已同步 Rust 后端二进制 (%s-%s)：\n' "$os" "$arch"
printf -- '- %s\n' "$ASSET_BIN"
printf -- '- %s\n' "$SKILL_BIN"
