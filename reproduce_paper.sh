#!/bin/bash
# MediSSI-Auth — Master reproduction script.
#
# Reproduces every §VI number on a fresh Ubuntu 24 machine in ~10 minutes
# (or ~45 minutes if the optional ZK trusted-setup is run).
#
# Usage:
#   ./reproduce_paper.sh
#
# Outputs:
#   data/measurements/*.json    — raw measurement files
#   figures/*.{pdf,png}         — publication-ready figures
#   docs/proverif/output.txt    — ProVerif analysis output (if installed)

set -e
set -o pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_ROOT"

# ---- pretty printing ----

bar()  { printf '=%.0s' {1..70}; echo; }
step() { echo; bar; echo "→ $*"; bar; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ! $*"; }
fail() { echo "  ✗ $*"; exit 1; }

step "MediSSI-Auth — reproduction driver"
echo "  Project root: $PROJECT_ROOT"
echo "  Started:      $(date -Iseconds)"

# ---- 1. Environment check ----

step "Step 1: Environment check"

if ! command -v python3 >/dev/null; then fail "python3 not found"; fi
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
ok "Python $PY_VER"

if ! command -v node >/dev/null; then fail "node not found"; fi
ok "Node $(node --version)"

# Python deps
python3 -c "import fastapi, web3, httpx, pytest, pytest_asyncio" 2>/dev/null || \
    fail "Missing Python deps. Run: pip install -r requirements.txt --break-system-packages"
ok "Python deps OK"

# matplotlib (for figures)
python3 -c "import matplotlib" 2>/dev/null && ok "matplotlib OK" || \
    warn "matplotlib missing — figure generation will be skipped"

# Snarkjs (via npm in scripts/node_modules — see scripts/setup_environment.sh)
SNARKJS=""
for p in scripts/node_modules/snarkjs/build/cli.cjs \
         ../stage4/scripts/node_modules/snarkjs/build/cli.cjs; do
    if [ -f "$PROJECT_ROOT/$p" ] || [ -f "$p" ]; then
        SNARKJS="$p"
        break
    fi
done
if [ -n "$SNARKJS" ]; then
    ok "snarkjs at $SNARKJS"
else
    warn "snarkjs not found — ZK tests will be skipped"
    warn "  fix: cd scripts && npm install snarkjs"
fi

# ProVerif (optional — for §VII)
if command -v proverif >/dev/null; then
    ok "ProVerif $(proverif -in "" 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1 || echo 'installed')"
else
    warn "ProVerif not installed — formal verification step will be skipped"
fi

# ---- 2. Boot test chain + deploy contracts ----

step "Step 2: Boot Ganache + deploy contracts"

if [ -x scripts/setup_test_chain.sh ]; then
    ./scripts/setup_test_chain.sh
    ok "Test chain ready"
else
    fail "scripts/setup_test_chain.sh not found"
fi

# ---- 3. Compile contracts (refresh ABIs + bytecode) ----

step "Step 3: Compile Solidity contracts"

if [ -f scripts/compile_contracts.js ] && [ -d scripts/solc_node_modules ]; then
    node scripts/compile_contracts.js
    ok "Contracts compiled"
else
    warn "scripts/compile_contracts.js or solc_node_modules missing — using cached build artifacts"
fi

# ---- 4. Run all 11 functional tests (§VI.B) ----

step "Step 4: §VI.B Functional correctness (11 tests)"
python3 -m pytest tests/ -v --tb=short 2>&1 | tail -20

# ---- 5. §VI.D Latency benchmarks ----

step "Step 5: §VI.D Latency (no-ZK, n=30)"
python3 scripts/measure_latency.py --n 30 --no-zk 2>&1 | tail -15

step "Step 6: §VI.D Latency (with ZK, n=5 — slower)"
python3 scripts/measure_latency.py --n 5 --zk 2>&1 | tail -15

# ---- 7. §VI.E Storage ----

step "Step 7: §VI.E Storage measurement"
python3 scripts/measure_storage.py 2>&1 | tail -25

# ---- 8. §VI.F Nexa comparison ----

step "Step 8: §VI.F Nexa comparison"
python3 scripts/compare_nexa.py 2>&1 | tail -15

# ---- 9. §VI.G TPS smoke test (Ganache lower-bound) ----

step "Step 9: §VI.G TPS smoke test (Ganache lower-bound, n=100)"
python3 scripts/measure_tps.py --n 100 --workers 20 2>&1 | tail -25

# ---- 10. Generate all §VI figures ----

step "Step 10: Generate §VI figures"
if python3 -c "import matplotlib" 2>/dev/null; then
    python3 scripts/generate_figures.py
    ok "Figures generated under figures/"
else
    warn "Skipped (matplotlib not installed)"
fi

# ---- 11. ProVerif structural validation ----

step "Step 11: ProVerif model validation"
python3 scripts/validate_proverif_model.py docs/proverif/medissi.pv 2>&1 | tail -10

if command -v proverif >/dev/null; then
    echo
    echo "→ Running full ProVerif analysis"
    proverif docs/proverif/medissi.pv > docs/proverif/output.txt 2>&1 || true
    echo "ProVerif results:"
    grep "^RESULT" docs/proverif/output.txt || warn "No RESULT lines (output may have errored)"
else
    warn "ProVerif not installed — skipping full analysis"
    warn "  install: opam install proverif -y"
fi

# ---- 12. Final summary ----

step "Reproduction complete"
echo
echo "Results:"
echo "  data/measurements/  — $(find data/measurements -name '*.json' 2>/dev/null | wc -l) JSON files"
echo "  figures/            — $(find figures -name '*.pdf' 2>/dev/null | wc -l) PDF files"
echo "  docs/proverif/      — $([ -f docs/proverif/output.txt ] && echo 'analysis run' || echo 'model only')"
echo
echo "Headline numbers:"
if [ -f data/measurements/storage.json ]; then
    python3 -c "
import json
d = json.load(open('data/measurements/storage.json'))
print(f'  Encrypted VC blob:     {d[\"vc_sizes\"][\"average\"][\"encrypted_bytes\"]} bytes')
print(f'  On-chain per cred:     {d[\"onchain_anchor\"][\"amortised_per_credential_bytes\"]:.2f} bytes')
print(f'  Reduction vs naive:    {d[\"vs_naive_full_onchain\"][\"reduction_factor\"]:,.0f}x')
"
fi

echo
echo "Notes:"
echo "  • For real-circuit ZK proofs (Stage 4 selective_disclosure circuit),"
echo "    run ./scripts/run_zk_setup.sh (one-time, ~25-40 min)."
echo "  • For §VI.G full 20K-tx target (≥320 TPS, ≤1.5s mean), run on Hyperledger"
echo "    Besu testnet with 4 IBFT 2.0 validators. See README.md."
echo "  • For ProVerif analysis without an opam install, the validator script"
echo "    confirms structural correctness."
echo
echo "Finished: $(date -Iseconds)"
