"""`python3 -m http.server PORT` for tests, minus its hostname lookup.

HTTPServer.server_bind calls socket.getfqdn() between bind() and listen(). On GitHub's macOS
runners that lookup goes to mDNS and can hang for minutes, so the server never listens and
provision.sh reports "not ready" (CI evidence: stack in _mdns_search_ex, 2026-11-21). The name
is only used for display; everything else is the stdlib server unchanged.
"""
import runpy
import socket

socket.getfqdn = lambda name='': name
runpy.run_module('http.server', run_name='__main__', alter_sys=True)
