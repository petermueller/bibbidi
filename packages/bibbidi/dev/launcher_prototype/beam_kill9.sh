#!/bin/sh
# Case 4: kill -9 the BEAM that owns the Browser; the wrapper alone must clean up.
#   sh dev/launcher_prototype/beam_kill9.sh            # real Firefox
#   BBD_FAKE_FIREFOX=1 sh dev/launcher_prototype/beam_kill9.sh
set -u
out=$(mktemp)
mix run dev/launcher_prototype/beam_kill9_victim.exs > "$out" 2>&1 &
mixpid=$!
for _ in $(seq 1 120); do grep -q '^VICTIM' "$out" && break; sleep 0.5; done
line=$(grep '^VICTIM' "$out") || { echo "victim never reported"; cat "$out"; kill -9 $mixpid; exit 1; }
echo "4) kill -9 of the BEAM: $line"
beam=$(echo "$line" | sed 's/.*beam=\([0-9]*\).*/\1/')
pgid=$(echo "$line" | sed 's/.*pgid=\([0-9]*\).*/\1/')
profile=$(echo "$line" | sed 's/.*profile=\(.*\)$/\1/')
echo "  group before: $(ps -A -o pid=,pgid=,comm= | awk -v g="$pgid" '$2==g' | wc -l | tr -d ' ') procs; profile dir exists: $([ -d "$profile" ] && echo yes || echo no)"
start=$(date +%s)
kill -9 "$beam"
for _ in $(seq 1 100); do
  n=$(ps -A -o pid=,pgid= | awk -v g="$pgid" '$2==g' | wc -l | tr -d ' ')
  [ "$n" = "0" ] && break
  sleep 0.1
done
end=$(date +%s)
echo "  group after BEAM kill -9: $n procs, ~$((end - start)) s; profile dir exists: $([ -d "$profile" ] && echo yes || echo no)"
ps -A -o pid=,pgid=,comm= | awk -v g="$pgid" '$2==g'
rm -f "$out"
