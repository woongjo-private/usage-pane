#!/bin/bash
# UsageBar 의 순수 함수를 Tests.swift 로 확인한다.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -swift-version 5 -module-cache-path build/ModuleCache -parse-as-library -D USAGEBAR_TESTS -o build/UsageBarTests UsageBar.swift CodexUsage.swift Tests.swift
./build/UsageBarTests "$@"
