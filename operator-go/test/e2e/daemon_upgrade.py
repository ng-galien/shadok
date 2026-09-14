#!/usr/bin/env python3
"""Upgrade a released daemon, retain its job, and publish by session without local YAML.
Usage: daemon_upgrade.py NEW_CLI RELEASED_CLI
"""
import http.server, json, os, pathlib, socket, subprocess, sys, tempfile, threading, time, urllib.request
new, old = map(lambda p: str(pathlib.Path(p).resolve()), sys.argv[1:3])
with tempfile.TemporaryDirectory(prefix='shadok-daemon-upgrade-') as td:
    base = pathlib.Path(td)
    source = base/'out'; source.mkdir(); (source/'file').write_text('first')
    target = base/'received'; target.mkdir()
    env = dict(os.environ, SHADOK_STATE_DIR=str(base/'state'), KUBECONFIG=str(base/'absent'))
    env.pop('SHADOK_DESTINATION', None); env.pop('SHADOK_URL', None)
    with socket.socket() as sock:
        sock.bind(('127.0.0.1', 0)); port = sock.getsockname()[1]
    receiver_url = f'http://127.0.0.1:{port}'
    receiver = subprocess.Popen([new, 'receive', '--listen', f'127.0.0.1:{port}', '--roots', json.dumps({'app':str(target)})], stdout=subprocess.DEVNULL)
    class Gateway(http.server.BaseHTTPRequestHandler):
        def log_message(self, *args): pass
        def do_GET(self):
            assert self.path == '/sessions/team/live'
            self.send_response(200); self.end_headers()
            self.wfile.write(b'{"roots":[{"mount":"app","path":"out"}]}')
        def do_POST(self):
            assert self.path in ('/sessions/team/live/plan','/sessions/team/live/apply')
            if self.headers.get('Transfer-Encoding') == 'chunked':
                chunks=[]
                while True:
                    size=int(self.rfile.readline().split(b';')[0],16)
                    if not size:
                        self.rfile.readline(); break
                    chunks.append(self.rfile.read(size)); self.rfile.read(2)
                body=b''.join(chunks)
            else:
                body = self.rfile.read(int(self.headers['Content-Length']))
            req = urllib.request.Request(receiver_url+'/'+self.path.rsplit('/',1)[1], body)
            with urllib.request.urlopen(req) as response:
                self.send_response(response.status); self.end_headers(); self.wfile.write(response.read())
    gateway = http.server.ThreadingHTTPServer(('127.0.0.1',0),Gateway)
    threading.Thread(target=gateway.serve_forever,daemon=True).start()
    def cli(binary,*args):
        p=subprocess.run([binary,*args],cwd=base,env=env,text=True,capture_output=True,timeout=35)
        assert p.returncode == 0, p.stdout+p.stderr
        return p.stdout
    config=base/'legacy.json'
    config.write_text(json.dumps({'version':1,'groups':{'source':{'mode':'watch','roots':[{'mount':'app','path':str(source)}]}}}))
    legacy=['--config',str(config),'--group','source','--receiver-url',receiver_url,'--timeout','20s']
    session=['--session','team/live','--url',f'http://127.0.0.1:{gateway.server_port}','--timeout','20s']
    try:
        cli(old,'watch',*legacy)
        old_ids={j['id'] for j in json.loads(cli(old,'status'))}
        config.unlink() # The session path cannot fall back to this file.
        cli(new,'publish',*session)
        jobs=json.loads(cli(new,'status'))
        assert old_ids.issubset({j['id'] for j in jobs}), 'lost legacy job during replacement'
        assert (target/'file').read_text() == 'first'
        inode=(base/'state/daemon.sock').stat().st_ino
        cli(new,'publish',*session)
        assert inode == (base/'state/daemon.sock').stat().st_ino, 'compatible daemon restarted'
        assert not (base/'shadok.yaml').exists()
        print('PASS: released daemon automatically replaced; legacy job retained; session publication succeeds without local config; compatible daemon reused')
    finally:
        subprocess.run([new,'daemon','stop'],env=env,capture_output=True,timeout=10)
        time.sleep(.3)
        gateway.shutdown(); gateway.server_close()
        receiver.terminate(); receiver.wait(timeout=5)
