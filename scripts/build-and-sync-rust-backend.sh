#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SOURCE_BIN="$ROOT_DIR/rust-cli/target/release/vtt-to-lrc-rust"
ASSET_BIN="$ROOT_DIR/assets/backend/vtt-to-lrc-macos-arm64"
SKILL_BIN="$ROOT_DIR/skill-package/vtt-to-lrc/scripts/vtt-to-lrc-macos-arm64"

cargo build --release --manifest-path "$ROOT_DIR/rust-cli/Cargo.toml"
cp "$SOURCE_BIN" "$ASSET_BIN"
chmod +x "$ASSET_BIN"
cp "$SOURCE_BIN" "$SKILL_BIN"
chmod +x "$SKILL_BIN"

printf '%s\n' "已同步 Rust 后端二进制："
printf '%s\n' "- $ASSET_BIN"
printf '%s\n' "- $SKILL_BIN"
