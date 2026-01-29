#!/bin/bash
# Build Selene with vendored Lua

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

LUA_VERSION="5.4.7"
LUA_DIR="native/lua"

# Download Lua source if not present
if [ ! -f "$LUA_DIR/lua.h" ]; then
    echo "Downloading Lua $LUA_VERSION..."
    mkdir -p "$LUA_DIR"
    LUA_URL="https://www.lua.org/ftp/lua-${LUA_VERSION}.tar.gz"

    curl -L -o /tmp/lua.tar.gz "$LUA_URL"
    tar -xzf /tmp/lua.tar.gz -C /tmp
    cp -r /tmp/lua-${LUA_VERSION}/src/* "$LUA_DIR/"
    rm -rf /tmp/lua.tar.gz /tmp/lua-${LUA_VERSION}

    echo "Lua source downloaded!"
fi

# Build the specified target
TARGET="${1:-Selene}"

echo "Building $TARGET..."
lake build "$TARGET"

echo "Build complete!"
