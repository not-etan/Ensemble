#!/bin/sh
# Raid test build (raid-prototype branch): one zip with both folders, Ensemble/ and Ensemble_Raid/,
# to unzip into World of Warcraft/_retail_/Interface/AddOns. For the author's in-game testing only;
# the release automation (.pkgmeta) never packages Ensemble_Raid.
set -e
cd "$(dirname "$0")/../.."
python3 tests/raid/run_raid_tests.py > /dev/null || { echo "raid tests failed"; exit 1; }
CORE=$(sed -n 's/^## Version: //p' Ensemble/Ensemble.toc | tr -d '\r')
RAID=$(sed -n 's/^## Version: //p' Ensemble_Raid/Ensemble_Raid.toc | tr -d '\r')
mkdir -p dist
OUT="dist/Ensemble-${CORE}+Raid-${RAID}.zip"
rm -f "$OUT"
python3 - "$OUT" <<'EOF'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for folder in ("Ensemble", "Ensemble_Raid"):
        for root, dirs, files in os.walk(folder):
            dirs.sort()
            for f in sorted(files):
                p = os.path.join(root, f)
                z.write(p, p)
print(out)
EOF
