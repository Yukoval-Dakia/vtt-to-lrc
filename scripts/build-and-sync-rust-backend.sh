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
ASSET_STAMP="$ROOT_DIR/assets/backend/${binary_name}.stamp"
SKILL_BIN="$ROOT_DIR/skill-package/vtt-to-lrc/scripts/$binary_name"

cargo build --release --manifest-path "$ROOT_DIR/rust-cli/Cargo.toml"
mkdir -p "$(dirname "$ASSET_BIN")" "$(dirname "$SKILL_BIN")"
cp "$SOURCE_BIN" "$ASSET_BIN"
chmod +x "$ASSET_BIN"
cp "$SOURCE_BIN" "$SKILL_BIN"
chmod +x "$SKILL_BIN"

# 写入 SHA-256 + 字节长度，供 Flutter 启动时快速比对，避免每次冷启动都重读整段资源。
# 跨平台：shasum (macOS 自带) / sha256sum (Linux 常见)；wc -c 比 stat 在 BSD/GNU 间更稳。
if command -v shasum >/dev/null 2>&1; then
  HASH=$(shasum -a 256 "$ASSET_BIN" | awk '{ print $1 }')
elif command -v sha256sum >/dev/null 2>&1; then
  HASH=$(sha256sum "$ASSET_BIN" | awk '{ print $1 }')
else
  printf '错误: 找不到 shasum 或 sha256sum 工具，无法生成 stamp\n' >&2
  exit 1
fi
SIZE=$(wc -c < "$ASSET_BIN" | tr -d ' ')
printf '%s\n%s\n' "$HASH" "$SIZE" > "$ASSET_STAMP"

printf '已同步 Rust 后端二进制 (%s-%s)：\n' "$os" "$arch"
printf -- '- %s\n' "$ASSET_BIN"
printf -- '- %s\n' "$SKILL_BIN"
printf -- '- %s（SHA-256: %s，size: %s）\n' "$ASSET_STAMP" "$HASH" "$SIZE"
