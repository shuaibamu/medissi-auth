# MediSSI-Auth — Reproducibility Artifact v1.0

This is the reproducibility artifact for the manuscript:

> **MediSSI-Auth: A Self-Sovereign Identity Authentication Framework with Zero-Knowledge Selective Disclosure for Cross-Organizational Electronic Health Records**


## What's in here

| Path | Contents |
|---|---|
| `src/agents/` | Three FastAPI services: Issuer, Patient, Verifier (Stages 6-7) |
| `src/crypto/` | EdDSA-Poseidon + Merkle + ChaCha20-Poly1305 (Stage 3) |
| `src/zkp/` | Circom 13,775-constraint selective-disclosure circuit + prover (Stage 4) |
| `src/data/` | NexaEHR ingestion pipeline (Stage 2) |
| `contracts/` | DIDRegistry, SchemaRegistry, RevocationRegistry, SDVerifier (Stages 5, 7) |
| `tests/` | 11 integration tests covering the full system (5+4+2 across three layers) |
| `scripts/` | Measurement, comparison, figure-generation scripts (Stage 8) |
| `docs/proverif/` | ProVerif applied pi calculus model (Stage 9) |
| `docs/compliance_mapping.md` | HIPAA + GDPR mapping (Stage 9) |
| `docs/sequence/` | Mermaid sequence + architecture diagrams |
| `data/processed/` | NexaEHR processed bins (998 patient bundles, small/medium/large) |
| `data/measurements/` | Raw measurement JSON outputs |
| `figures/` | Publication-ready PDF + PNG figures |
| `build/circuits/` | Compiled R1CS + WASM for the ZK circuit |
| `build/setup/` | Phase 1 trusted-setup `pot14_final.ptau` |
| `build/tier3_evidence/` | Tiny demo zkey + valid Groth16 proof |
| `build/contracts/` | Compiled Solidity ABIs + bytecode |
| `reproduce_paper.sh` | The master reproduction script |
| `MANIFEST.txt` | SHA-256 hashes of every file (integrity check) |

## Prerequisites

Tested on Ubuntu 24.04.x. The artifact needs:

| Tool | Version | Why |
|---|---|---|
| Python | 3.12+ | Agents, scripts, tests |
| Node.js | 22.x | snarkjs prover, Solidity compile |
| OCaml + opam | 4.14+ | ProVerif security analysis (optional) |
| Java | 21 LTS | Hyperledger Besu (only for §VI.G TPS measurement) |
| Hyperledger Besu | 24.x | 4-node IBFT 2.0 testnet (only for §VI.G) |

Install everything in one go:

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-pip nodejs npm ocaml opam openjdk-21-jdk
pip install -r requirements.txt --break-system-packages
opam init --bare --no-setup -y
eval $(opam env)
opam install proverif -y
```

Hyperledger Besu is downloaded separately from the Besu releases page (https://github.com/hyperledger/besu/releases). Skip if you only want the §VI.A–F + §VII reproduction (Ganache-only) — those constitute most of the manuscript's results.

## Quick reproduction

```bash
./reproduce_paper.sh
```

Expected wall-clock time: **~10 minutes** without ZK trusted-setup, **~45 minutes** with it.



## Optional: full ZK run (real circuit)

The default reproduction uses the **tiny_demo** circuit (200 constraints) for the ZK integration tests — same Groth16 toolchain, faster setup, identical integration semantics. To exercise the **real selective_disclosure circuit** (13,775 constraints):

```bash
# One-time, ~25-40 min on commodity hardware — single-threaded snarkjs WASM
./scripts/run_zk_setup.sh

# Then re-run reproduce_paper.sh; the prover auto-detects the real circuit
./reproduce_paper.sh
```

The real-circuit deliverable is the manuscript's primary §V.B claim. The tiny_demo's role is to demonstrate the **integration** is correct without making reviewers wait 30+ minutes for setup. Both produce verifiable Groth16 proofs accepted by the deployed SDVerifier.

## Optional: Besu §VI.G measurement

The manuscript's §VI.G TPS target (≥320 TPS sustained at ≤1.5s mean over 20,000 transactions, locked from [P31] Bai's Health-zkIDM benchmark) requires the actual 4-node Besu IBFT 2.0 testnet. Ganache's instamine model does not produce meaningful concurrent-mempool semantics.

```bash
# 1. Install Java 21 + Besu (one-time, ~10 min)
sudo apt install -y openjdk-21-jdk
# Download Besu 24.x binary from GitHub releases, add to PATH

# 2. Bootstrap the 4-node network (procedure documented in network/besu/bootstrap.sh
#    from the Stage 1 artifact; carried into the manuscript)

# 3. Deploy contracts to Besu
RPC_URL=http://127.0.0.1:8545 \
  PRIVATE_KEY=$(cat network/besu/node1/data/key | tr -d '\n') \
  node scripts/deploy.js

# 4. Run the §VI.G measurement
RPC_URL=http://127.0.0.1:8545 \
  python3 scripts/measure_tps.py --n 20000 --workers 200
```

## Optional: ProVerif security analysis

```bash
opam install proverif -y
proverif docs/proverif/medissi.pv > docs/proverif/output.txt 2>&1
grep "^RESULT" docs/proverif/output.txt
```

Expected runtime: <30 seconds. Three queries should report `is true`:
- Authenticity (injective correspondence)
- Confidentiality (non-disclosed attribute secrecy)
- Revocation safety (with the abstract-vs-state-machine caveat noted in `docs/proverif/expected_output.txt`)

## Headline numbers (from the included measurement files)

These are populated in `data/measurements/` from a Ganache reproduction; numbers from a Besu reproduction will differ on latency only (gas, storage are EVM-determined and identical).

### §VI.B Functional correctness

11 / 11 tests pass:

```
tests/test_agents.py ........... 5 passed
tests/test_zk_integration.py ... 4 passed
tests/test_onchain_verifier.py . 2 passed
============================== 11 passed in ~32s ==============================
```

### §VI.D Latency (no-ZK, n=30)

| Stage | Mean | p95 |
|---|---:|---:|
| Issue | 272 ms | 441 ms |
| Receive | 151 ms | 167 ms |
| Present | <1 ms | 1 ms |
| Verify | 104 ms | 116 ms |
| **End-to-end** | **527 ms** | 691 ms |

### §VI.E Storage

| Item | Bytes |
|---|---:|
| Plaintext VC (16 attrs JSON) | 2,390 |
| Encrypted VC blob (ChaCha20-Poly1305) | 2,418 |
| On-chain amortised per credential | 2.44 |
| **Reduction vs. naive on-chain FHIR** | **1.6 million×** |

### §VI.D Stage 5 contract gas

| Method | Gas |
|---|---:|
| DIDRegistry.register | 138,013 |
| SchemaRegistry.register | 184,807 |
| RevocationRegistry.revoke (warm) | 36,213 |
| **SDVerifier.verifyProof** | **216,832** |

### §VI.F vs. Nexa baseline

| Axis | Advantage |
|---|---|
| ZK selective disclosure | MediSSI-Auth has it; Nexa does not |
| On-chain anchor | 80× smaller (2.44 vs 200 bytes) |
| Verification latency | 125× faster on equivalent infrastructure |
| On-chain verifier | 217K gas verifyProof; Nexa: n/a |

## Scientific scope and caveats

Three honest caveats the manuscript addresses transparently:

1. **Trusted setup.** The Phase 2 ceremony for Groth16 was performed single-party for the research artifact (per ADR-011). Production deployment requires a multi-party ceremony to relax the single-honest-contributor assumption. Replacing the zkey is mechanical; the rest of the pipeline regenerates automatically.

2. **Ganache is not Besu.** Latency numbers reproduced from this artifact are Ganache (instamine, single-node). The qualitative ranking vs. Nexa is stable across infrastructures; absolute latencies will be 1-3 seconds higher on Besu (block-time bound). TPS is meaningless on Ganache; the §VI.G measurement requires Besu (procedure documented above).

3. **ProVerif's symbolic model.** The formal verification covers authenticity and confidentiality at the Dolev-Yao symbolic layer. It does not cover side-channel attacks (timing, cache, fault), which are addressed at the deployment layer with constant-time crypto libraries.

## Architectural decisions (ADRs)

All 15 numbered architectural decisions live in `docs/decisions.md`. Highlights:

- ADR-001: IPFS = Filebase (matches Nexa baseline)
- ADR-002: Besu validators = 4 (IBFT 2.0, BFT bound f<n/3)
- ADR-003: ZKP = Groth16 / Circom / snarkjs
- ADR-006: 16 attribute slots per credential
- ADR-008: Python Poseidon = circomlibpy 1.0.0 (alternatives silently produce wrong hashes)
- ADR-010: Phase 1 = research-grade local generation
- ADR-011: Phase 2 = single-party with disclosure
- ADR-013: Agent layer = FastAPI with dependency-injected state
- ADR-015: Solidity verifier requires Fp2 element swap for EIP-197

## License

Code: Apache-2.0  
Data and documentation: CC-BY-4.0  
NexaEHR dataset: governed by IEEE DataPort terms (DOI 10.21227/zg38-0317)


```bash
./scripts/verify_artifacts.sh
```
