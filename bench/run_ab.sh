#!/bin/bash
# run_template.sh - one A/B experiment on AiBox: cold server per arm, guard first, full logs, switch confirmation.
# Copy to notes/bench/eNNN/run_eNNN.sh, fill in the CONFIG block and the ARMS block, run inside tmux:
#   tmux new -d -s eNNN "bash notes/bench/eNNN/run_eNNN.sh > notes/bench/eNNN/report.out 2>&1"
# and watch report.out with a Monitor whose filter covers every end state ("=== |exit [^0]|DONE|guard|rror|Traceback").
#
# Built from E342-E352 (Strata serve harness). For llama.cpp / SGLang arms, keep the structure and replace the
# "start the server" and "stop the server" lines (llama-server --port 8089 ...; kill by pid), never `docker run`.
set -u

# ---------------------------------------------------------------- CONFIG (edit)
E=$HOME/bench/eNNN
PY=python3
PACK=$HOME/Strata-data/packs/iq3_s       # tokenizer for benchmark.py
SKILL=$(dirname "$0")
SPL=$HOME/prod-bin/strata-<build>/strata-split.json
TARGETS=4096,32768
RUNS=2
CONFIRM_RE='rocBLAS tuning enabled|run FP16 in and out|adaptive swaps copy with a kernel|pipeline'   # engine lines that prove a switch took effect

knob() { timeout 10 sudo -n /usr/local/bin/strata-gfxoff status 2>&1 | tr -s ' \n' ' '; }   # GFXOFF state (reference count! see pitfalls)
vram() { echo "card0 $(( $(cat /sys/class/drm/card0/device/mem_info_vram_used)/1048576 )) MiB, card1 $(( $(cat /sys/class/drm/card1/device/mem_info_vram_used)/1048576 )) MiB"; }

# arm <name> <worktree with build-hip/strata> <base config> <env a=b,c=d or -> [extra engine args...]
# optional env: NOBENCH=1 (skip benchmark.py), HOOK=<function> (called with $out while the server is up),
#               VISION_JSON='{...}' (adds a "vision" section; pair it with --vision --vram-reserve-mib 700, E349)
arm() {
  local name=$1 wt=$2 exe=$3 base=$4 envv=$5; shift 5; local out=$E/$name; mkdir -p "$out"
  "$SKILL/guard.sh" > /dev/null || { echo "=== $name guard failed"; return; }
  curl -s 127.0.0.1:9292/running | grep -q '"running":\[\]' || { echo "=== $name llama-swap busy"; return; }
  python3 - "$name" "$wt" "$exe" "$base" "$out" "$envv" "$@" <<'PY'
import json, os, sys
name, wt, exe, base, out, envv, extra = sys.argv[1:7] + [sys.argv[7:]]
j = json.load(open(base)); a = list(j['args'])
j['args'] = a + extra; j['exe'] = exe; j['cwd'] = wt; j['log'] = f'{out}/engine.log'
if os.environ.get('GPU_ORDER'): j['gpu_order'] = os.environ['GPU_ORDER']
for k, e in (('--spec', 'SPEC'), ('--spec-min-p', 'MINP')):
    if os.environ.get(e):
        i = j['args'].index(k); j['args'][i+1] = os.environ[e]
env = dict(j.get('env') or {})
if envv != '-':
    for kv in envv.split(','):
        k, v = kv.split('=', 1); env[k] = v
j['env'] = env
if os.environ.get('VISION_JSON'): j['vision'] = json.loads(os.environ['VISION_JSON'])
json.dump(j, open(f'{out}/config.json', 'w'), indent=2)
PY
  rm -f "$out"/engine.log "$out"/server.out "$out"/telemetry.jsonl
  python3 "$SKILL/monitor_amd.py" "$out/telemetry.jsonl" & local mon=$!
  (cd "$wt" && tmux new -d -s strata-run "$PY serve/server.py --engine strata --config $out/config.json --port 8089 > $out/server.out 2>&1")
  for i in $(seq 200); do grep -qiE 'ready:|error|fail|stopped|unexpectedly' "$out/server.out" 2>/dev/null && break; sleep 3; done
  local pid=$(for p in /proc/[0-9]*; do [ "$(readlink $p/exe 2>/dev/null)" = "$exe" ] && basename $p; done | head -1)
  { echo "name $name"; echo "worktree $wt $(git -C "$wt" log -1 --format='%H %s' | cut -c1-120)";
    echo "binary sha256 $(sha256sum "$exe" | cut -d' ' -f1)"; echo "env $envv"; echo "extra args $*";
    echo "gfxoff knob at start: $(knob)";
    grep -E "^(STRATA_|CMAKE_HIP_ARCH|CMAKE_BUILD_TYPE|GPU_TARGETS)" "$wt/build-hip/CMakeCache.txt" 2>/dev/null | grep -v "_DIR\|INTERNAL" | tr '\n' ' '; echo; } > "$out/BUILD.txt"
  echo "=== $name start $(date +%T) pid $pid knob $(knob)"
  [ "${NOBENCH:-0}" = 1 ] || { timeout 3000 $PY "$SKILL/benchmark.py" --root "$wt" --pack "$PACK" --url http://127.0.0.1:8089 --out "$out" --targets $TARGETS --runs $RUNS > "$out/benchmark.out" 2>&1; echo "$name benchmark exit $?"; }
  [ -n "${HOOK:-}" ] && $HOOK "$out"
  echo "  $name vram: $(vram)"
  curl -s http://127.0.0.1:8089/v1/status > "$out/final-status.json"
  tmux send-keys -t strata-run C-c; sleep 8; tmux kill-session -t strata-run 2>/dev/null
  for i in $(seq 60); do [ -d /proc/$pid ] || break; sleep 2; done
  kill $mon 2>/dev/null
  echo "=== $name done $(date +%T): stalls $(grep -cE 'stall report|timed out at layer|no progress for' "$out/engine.log"); confirm lines $(grep -cE "$CONFIRM_RE" "$out/engine.log")"
}

# ---------------------------------------------------------------- ARMS
# E385: --spec {3,4,6} at min-p 0.5; --spec-min-p {0.3,0.5,0.7} at spec 4. Binary/config = production strata-141-d14ca361.
PROD=$HOME/prod-bin/strata-<build>
for r in 1 2; do
  arm P$r $PROD $PROD/strata-engine "$SPL" -
  SPEC=3   arm S3-$r $PROD $PROD/strata-engine "$SPL" -
  SPEC=6   arm S6-$r $PROD $PROD/strata-engine "$SPL" -
  MINP=0.3 arm M3-$r $PROD $PROD/strata-engine "$SPL" -
  MINP=0.7 arm M7-$r $PROD $PROD/strata-engine "$SPL" -
done
echo "E385 DONE $(date +%T)"
