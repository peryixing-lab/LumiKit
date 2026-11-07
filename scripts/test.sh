#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
LUMI_NODE_BIN="${LUMI_NODE_BIN:-/Applications/DevEco-Studio.app/Contents/tools/node/bin/node}"
"$LUMI_NODE_BIN" entry/src/test/DeveloperUtils.spec.cjs
"$LUMI_NODE_BIN" scripts/test-file-data.cjs
"$LUMI_NODE_BIN" scripts/tests/forms_inventory.spec.cjs
"$LUMI_NODE_BIN" scripts/test-storage.cjs
"$LUMI_NODE_BIN" scripts/test-task-manager.cjs
"$LUMI_NODE_BIN" scripts/test-next-release.cjs
"$LUMI_NODE_BIN" scripts/test-workbench.cjs
"$LUMI_NODE_BIN" scripts/test-image-compression.cjs
"$LUMI_NODE_BIN" scripts/test-search.cjs
"$LUMI_NODE_BIN" scripts/test-material-packs.cjs
"$LUMI_NODE_BIN" scripts/test-batch-files.cjs
"$LUMI_NODE_BIN" scripts/test-release13.cjs
