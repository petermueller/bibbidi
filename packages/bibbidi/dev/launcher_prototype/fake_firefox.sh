#!/bin/sh
# Stand-in for Firefox when the real one is unavailable: same CLI shape, same
# banner line, and a small process tree (two "content processes") so the
# group-kill path has something to sweep. Dies on TERM like Firefox does.
port=0
while [ $# -gt 0 ]; do
  case "$1" in
    --remote-debugging-port) port=$2; shift 2 ;;
    *) shift ;;
  esac
done
sleep 100000 &
sleep 100000 &
echo "*** fake firefox pid=$$"
sleep 0.3
echo "WebDriver BiDi listening on ws://127.0.0.1:$port"
wait
