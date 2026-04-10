#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
BIN="$SCRIPT_DIR/vtt-to-lrc-macos-arm64"
OS_NAME=$(uname -s)
ARCH_NAME=$(uname -m)

if [ "$OS_NAME" != "Darwin" ] || [ "$ARCH_NAME" != "arm64" ]; then
  echo "当前 skill 仅内置 macOS arm64 二进制，当前环境为 ${OS_NAME} ${ARCH_NAME}。" >&2
  exit 2
fi

if [ ! -x "$BIN" ]; then
  echo "缺少可执行文件: $BIN" >&2
  exit 2
fi

exec "$BIN" "$@"
