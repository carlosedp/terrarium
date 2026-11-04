#!/usr/bin/env python3
"""Send Lua to a norns matron REPL over websocket and print what comes back.

usage: nrepl.py [--host H] [--wait SECONDS] 'lua code' ['more lua' ...]
"""
import argparse, time, websocket

ap = argparse.ArgumentParser()
ap.add_argument("--host", default="localhost")
ap.add_argument("--wait", type=float, default=1.5)
ap.add_argument("code", nargs="+")
a = ap.parse_args()

ws = websocket.create_connection(f"ws://{a.host}:5555/", subprotocols=["bus.sp.nanomsg.org"], timeout=10)
ws.settimeout(0.2)
for c in a.code:
    ws.send(c + "\n")
end = time.time() + a.wait
while time.time() < end:
    try:
        msg = ws.recv()
        print(msg if isinstance(msg, str) else msg.decode(errors="replace"), end="")
    except websocket.WebSocketTimeoutException:
        pass
ws.close()
