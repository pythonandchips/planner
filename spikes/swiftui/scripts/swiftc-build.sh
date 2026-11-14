#!/bin/bash
# Builds the package with swiftc directly, without SwiftPM.
#
# Why: inside a Seatbelt sandbox where the per-user temp dir
# (/var/folders/.../T) is not writable, SwiftPM fails on its atomic writes
# ("You don't have permission to save the file output-file-map.json").
# Outside such a sandbox, use `swift build` / `swift test` instead.
#
# Usage: scripts/swiftc-build.sh [test|app|release] (default: test)
#   test     build PlannerCore + tests into a runner and run swift-testing
#   app      debug build of the app at $OUT/PlannerDesk
#   release  -O build of the app at $OUT/PlannerDesk-release
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/.build/swiftc}"
TMP_BASE="${TMPDIR:-/tmp}"
MODCACHE="${MODCACHE:-$OUT/modcache}"
FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
mkdir -p "$OUT" "$MODCACHE"
export CLANG_MODULE_CACHE_PATH="$MODCACHE"

COMMON=(-swift-version 6 -target arm64-apple-macosx14.0 -module-cache-path "$MODCACHE")
MODE="${1:-test}"

build_core() { # $1 = extra flags (e.g. -O or -enable-testing)
    swiftc "${COMMON[@]}" $1 -parse-as-library -module-name PlannerCore \
        -emit-library -static -emit-module -emit-module-path "$OUT/PlannerCore.swiftmodule" \
        -o "$OUT/libPlannerCore.a" "$ROOT"/Sources/PlannerCore/*.swift
}

case "$MODE" in
core)
    build_core "-Onone -g"
    echo "built $OUT/libPlannerCore.a"
    ;;
test)
    build_core "-Onone -enable-testing -g"
    cat > "$OUT/TestMain.swift" <<'EOF'
import Testing
@main struct Runner {
    static func main() async { await Testing.__swiftPMEntryPoint() as Never }
}
EOF
    swiftc "${COMMON[@]}" -Onone -g -module-name PlannerCoreTests -parse-as-library \
        -I "$OUT" -L "$OUT" -lPlannerCore \
        -F "$FRAMEWORKS" -I "$FRAMEWORKS" -framework Testing -Xfrontend -disable-cross-import-overlays \
        -plugin-path /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker /Library/Developer/CommandLineTools/usr/lib/swift/macosx/testing \
        "$ROOT"/Tests/PlannerCoreTests/*.swift "$OUT/TestMain.swift" -o "$OUT/PlannerCoreTests"
    mkdir -p "$TMP_BASE/planner-desk-tests"
    PLANNER_TEST_TMP="$TMP_BASE/planner-desk-tests" "$OUT/PlannerCoreTests" "${@:2}"
    ;;
app)
    build_core "-Onone -g"
    swiftc "${COMMON[@]}" -Onone -g -parse-as-library -module-name PlannerDesk \
        -I "$OUT" -L "$OUT" -lPlannerCore "$ROOT"/Sources/PlannerDesk/*.swift -o "$OUT/PlannerDesk"
    echo "built $OUT/PlannerDesk"
    ;;
release)
    build_core "-O -wmo"
    swiftc "${COMMON[@]}" -O -wmo -parse-as-library -module-name PlannerDesk \
        -I "$OUT" -L "$OUT" -lPlannerCore "$ROOT"/Sources/PlannerDesk/*.swift -o "$OUT/PlannerDesk-release"
    strip -x "$OUT/PlannerDesk-release" 2>/dev/null || true
    ls -lh "$OUT/PlannerDesk-release"
    ;;
probe)
    build_core "-Onone -g"
    swiftc "${COMMON[@]}" -Onone -parse-as-library -module-name AcpProbe \
        -I "$OUT" -L "$OUT" -lPlannerCore "$ROOT/scripts/AcpProbe.swift" -o "$OUT/acp-probe"
    "$OUT/acp-probe" "${@:2}"
    ;;
*) echo "usage: $0 [test|app|release|probe]" >&2; exit 2 ;;
esac
