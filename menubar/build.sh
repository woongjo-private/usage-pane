#!/bin/bash
# UsageBar.app 을 build/ 에 만든다. Xcode Command Line Tools 의 swiftc 만 쓴다.
set -euo pipefail
cd "$(dirname "$0")"

APP=build/UsageBar.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
swiftc -O -swift-version 5 -module-cache-path build/ModuleCache -parse-as-library -o "$APP/Contents/MacOS/UsageBar" UsageBar.swift CodexUsage.swift
# 서명이 없으면 실행할 때마다 Gatekeeper 가 막아 ad-hoc 서명을 붙인다.
codesign --force --sign - "$APP"
echo "$PWD/$APP"
