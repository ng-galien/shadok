#!/usr/bin/env python3
"""Docker Desktop loopback -> Kind NodePort, opaque TCP (no HTTP/TLS handling)."""
import select,socket,socketserver,threading
NODE='shadok-go-e2e-control-plane'
class Forward(socketserver.BaseRequestHandler):
    def handle(self):
        with socket.create_connection((NODE,self.server.target),timeout=10) as upstream:
            upstream.settimeout(None)
            streams=[self.request,upstream]
            while streams:
                readable,_,_=select.select(streams,[],[],190)
                if not readable:return
                for source in readable:
                    data=source.recv(65536)
                    if not data:return
                    (upstream if source is self.request else self.request).sendall(data)
class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address=True
    daemon_threads=True
for local,remote in [(8080,30080),(8443,30443)]:
    server=Server(('0.0.0.0',local),Forward);server.target=remote
    threading.Thread(target=server.serve_forever,daemon=True).start()
threading.Event().wait()
