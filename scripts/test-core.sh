#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/localization.py --check
python3 scripts/prepare-core.py
go test -race -tags cli ./...
go test -tags cli app/backend
go vet -tags cli ./...
go build -tags cli -buildmode=c-archive -o .build/libgotohp.a ./cmd/bridge
libs=(-lpthread -lm)
if [[ $(uname -s) == Linux ]]; then libs+=(-ldl); fi
if [[ $(uname -s) == Darwin ]]; then libs+=(-framework CoreFoundation -framework Security); fi
${CC:-cc} -I.build tests/bridge_smoke.c .build/libgotohp.a "${libs[@]}" -o .build/bridge-smoke
.build/bridge-smoke
