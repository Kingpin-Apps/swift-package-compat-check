#!/usr/bin/env bash
#
# bench-runtimes.sh — compare spcc container runtimes on one package.
#
# Runs `spcc run` once per runtime with fresh caches, then tabulates per-cell
# wall-clock, pass/fail parity, and qemu-IPC retry counts. Methodology mirrors
# the "lean parity test" in the spcc-apple-container-runtime wiki note: one
# package × one (or few) Swift version(s) × a few platforms, cold caches.
#
# Usage:
#   scripts/bench-runtimes.sh <pkg-path> [-p platforms] [-s versions]
#                             [-r "runtime ..."] [--label TAG] [-o OUTDIR]
#                             [--no-warmup]
#
# Examples:
#   scripts/bench-runtimes.sh ../swift-cardano-core
#   scripts/bench-runtimes.sh ../swift-cardano-core -r "container podman" --label libkrun
#
# Notes:
#   - Each runtime's daemon/machine must already be up (docker desktop /
#     `container system start` / `podman machine start`); spcc's own preflight
#     prints an actionable error otherwise and that runtime is skipped.
#   - Retries only occur on the cross-SDK path (android/wasm); linux never
#     retries, so its retry column is always 0.
#   - The spcc binary is taken from $SPCC_BIN, else `spcc` on PATH, else the
#     debug build under `swift build --show-bin-path`.
set -euo pipefail

# ---- args -------------------------------------------------------------------
PKG="${1:?usage: bench-runtimes.sh <pkg-path> [-p platforms] [-s versions] [-r \"runtimes\"] [--label TAG] [-o OUTDIR]}"
shift

PLATFORMS="linux,android,wasm"
VERSIONS="6.3"
RUNTIMES="container docker podman"
LABEL=""
OUTDIR=""
WARMUP=1     # pre-pull images (untimed) so timed cells exclude pull time; --no-warmup to skip
TIMEOUT=""   # optional per-cell wall-clock budget (seconds), passed to spcc --timeout

while [ $# -gt 0 ]; do
    case "$1" in
        -p) PLATFORMS="$2"; shift 2 ;;
        -s) VERSIONS="$2"; shift 2 ;;
        -r) RUNTIMES="$2"; shift 2 ;;
        --label) LABEL="$2"; shift 2 ;;
        -o) OUTDIR="$2"; shift 2 ;;
        --no-warmup) WARMUP=0; shift ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# spcc flags common to warm-up and timed runs. --timeout kills a hung cell so a
# runtime that wedges (e.g. Podman OOMing on concurrent heavy cells) fails fast
# instead of spinning forever.
SPCC_FLAGS=""
[ -n "$TIMEOUT" ] && SPCC_FLAGS="--timeout $TIMEOUT"

# ---- locate spcc ------------------------------------------------------------
if [ -n "${SPCC_BIN:-}" ]; then
    SPCC="$SPCC_BIN"
elif command -v spcc >/dev/null 2>&1; then
    SPCC="spcc"
else
    SPCC="$(swift build --show-bin-path)/spcc"
fi
[ -x "$SPCC" ] || { echo "spcc binary not found/executable: $SPCC" >&2; exit 1; }

TAG="${LABEL:+$LABEL-}"
: "${OUTDIR:=bench-results}"
mkdir -p "$OUTDIR"
TSV="$OUTDIR/${TAG}bench.tsv"
: > "$TSV"   # truncate
printf 'runtime\tplatform\tversion\tseconds\tresult\tretries\n' >> "$TSV"

echo "spcc:      $SPCC"
echo "package:   $PKG"
echo "platforms: $PLATFORMS   versions: $VERSIONS"
echo "runtimes:  $RUNTIMES"
echo "warm-up:   $([ "$WARMUP" = 1 ] && echo 'on (images pre-pulled, untimed)' || echo off)"
echo "output:    $TSV"
echo

# ---- per-runtime run --------------------------------------------------------
for rt in $RUNTIMES; do
    echo "=== runtime: $rt ==="
    stdout_log="$OUTDIR/${TAG}${rt}.stdout.log"

    # Cold caches so every runtime starts from the same state.
    "$SPCC" clean-all >/dev/null 2>&1 || true

    # Warm-up run (untimed, discarded). docker/podman pull images INLINE inside
    # the timed `run --pull=missing`, whereas apple/container pulls in a separate
    # pre-step; without this warm-up the first timed cell of each image would be
    # inflated by its (multi-GB) pull for docker/podman only — not comparable.
    # The warm-up pulls all needed images (and warms the build volume); the
    # clean-all below then restores a COLD build volume while keeping the images,
    # so the timed run measures cold-volume + warm-image for every runtime alike.
    if [ "$WARMUP" = "1" ]; then
        echo "  warming images (untimed)…"
        "$SPCC" run "$PKG" --container-runtime "$rt" \
            -p "$PLATFORMS" -s "$VERSIONS" $SPCC_FLAGS --no-live >/dev/null 2>&1 || true
        "$SPCC" clean-all >/dev/null 2>&1 || true   # drop volumes, keep images
    fi

    # --no-live forces the streaming path, which prints one
    #   "  ✓ linux × Swift 6.3 (12.3s)" line per cell that we parse below.
    set +e
    "$SPCC" run "$PKG" --container-runtime "$rt" \
        -p "$PLATFORMS" -s "$VERSIONS" $SPCC_FLAGS --no-live 2>&1 | tee "$stdout_log"
    rc="${PIPESTATUS[0]}"
    set -e
    echo "  (exit=$rc)"

    if [ "$rc" -ne 0 ] && ! grep -qE '× Swift .* \([0-9.]+s\)' "$stdout_log"; then
        # Runtime never produced a single cell (e.g. preflight failed: not
        # running). Record nothing for it; the table just omits the column.
        echo "  no cells ran for $rt (runtime down?) — skipping" >&2
        echo
        continue
    fi

    # Log dir spcc just used, from its "Logs:  <path>" header.
    logdir="$(grep -m1 '^Logs:' "$stdout_log" | sed -E 's/^Logs:[[:space:]]*//')"

    # Parse each cell line: "  <sym> <platform> × Swift <ver> (<secs>s)".
    while IFS=$'\t' read -r secs sym platform version; do
        [ -n "$secs" ] || continue
        case "$sym" in
            "✓") result="pass" ;;
            "✗") result="fail" ;;
            *)   result="$sym" ;;
        esac
        # Retry count for this cell from its per-cell log (cross-SDK only).
        retries=0
        cell_log="$logdir/${platform}-${version}.log"
        if [ -f "$cell_log" ]; then
            retries="$(grep -cE "Retry [0-9]+/[0-9]+ for SDK" "$cell_log" || true)"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$rt" "$platform" "$version" "$secs" "$result" "$retries" >> "$TSV"
    done < <(sed -nE \
        's/^[[:space:]]+([^[:space:]]+) ([^[:space:]]+) × Swift ([^[:space:]]+) \(([0-9.]+)s\)$/\4\t\1\t\2\t\3/p' \
        "$stdout_log")
    echo
done

# ---- comparison table -------------------------------------------------------
echo "===================== comparison ====================="
awk -F'\t' '
NR==1 { next }                                   # skip header
{
    rt=$1; cell=$2"-"$3; secs=$4; res=$5; ret=$6
    if (!(rt in seenrt)) { seenrt[rt]=1; order[++nrt]=rt }
    key=cell SUBSEP rt
    S[key]=secs; R[key]=res; T[key]=ret
    if (!(cell in seencell)) { seencell[cell]=1; cellorder[++ncell]=cell }
    # track pass/fail per cell across runtimes for the parity flag
    if (res=="pass" || res=="fail") {
        if (!(cell in firstres)) firstres[cell]=res
        else if (firstres[cell]!=res) parity[cell]=1
    }
}
END {
    # header
    printf "%-16s", "cell"
    for (i=1;i<=nrt;i++) printf "%-22s", order[i]
    printf "%s\n", "parity"
    printf "%-16s", ""
    for (i=1;i<=nrt;i++) printf "%-22s", "  s     res   retry"
    printf "\n"
    for (c=1;c<=ncell;c++) {
        cell=cellorder[c]
        printf "%-16s", cell
        for (i=1;i<=nrt;i++) {
            rt=order[i]; key=cell SUBSEP rt
            if (key in S) printf "%-22s", sprintf("%6s  %-4s  %s", S[key], R[key], T[key])
            else          printf "%-22s", "   -"
        }
        printf "%s\n", (cell in parity) ? "DIFFERS" : "ok"
    }
}
' "$TSV"

echo
echo "TSV written to: $TSV"
