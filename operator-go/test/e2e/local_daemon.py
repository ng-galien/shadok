#!/usr/bin/env python3
"""Real CLI/daemon/receiver process contract test; isolated temporary files only."""
import json, os, pathlib, socket, subprocess, tempfile, time
BIN = pathlib.Path(__file__).resolve().parents[2] / 'bin/shadok'
with tempfile.TemporaryDirectory(prefix='shadok-local-e2e-') as td:
    base=pathlib.Path(td); src=base/'source'; dst=base/'receiver'; src.mkdir();dst.mkdir()
    token=base/'token';token.write_text('test-only-token')
    config=base/'shadok.json';config.write_text(json.dumps({'version':1,'project':'test','groups':{'source':{'mode':'watch','roots':[{'mount':'app','path':str(src)}]},'compiled':{'mode':'build','roots':[{'mount':'app','path':str(src)}]}}}))
    sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
    env=dict(os.environ,SHADOK_STATE_DIR=str(base/'daemon'))
    receiver=None
    def start_receiver():
        return subprocess.Popen([str(BIN),'receive','--listen',f'127.0.0.1:{port}','--roots',json.dumps({'app':str(dst)}),'--token-file',str(token)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
    common=['--config',str(config),'--receiver-url',f'http://127.0.0.1:{port}','--token-file',str(token),'--timeout','20s']
    def cli(*args,ok=True):
        p=subprocess.run([str(BIN),*args],env=env,text=True,capture_output=True,timeout=45)
        if ok and p.returncode: raise AssertionError(p.stdout+p.stderr)
        if not ok and not p.returncode: raise AssertionError('unexpected success')
        return p
    def wait(path,value):
        for _ in range(120):
            if (path.read_text() if path.exists() else None)==value:return
            time.sleep(.1)
        raise AssertionError(f'{path}: expected {value!r}')
    try:
        receiver=start_receiver();(src/'file.txt').write_text('one');(dst/'baseline').write_text('delete me')
        cli('watch','--group','source',*common);wait(dst/'file.txt','one');wait(dst/'baseline',None)
        inode=(base/'daemon/daemon.sock').stat().st_ino
        cli('watch','--group','source',*common)
        assert inode==(base/'daemon/daemon.sock').stat().st_ino,'daemon replaced'
        (src/'file.txt').write_text('two');wait(dst/'file.txt','two')
        (src/'new.txt').write_text('added');wait(dst/'new.txt','added')
        (src/'file.txt').unlink();wait(dst/'file.txt',None)
        receiver.terminate();receiver.wait(timeout=5)
        (dst/'new.txt').unlink();receiver=start_receiver();wait(dst/'new.txt','added')
        cli('daemon','stop');time.sleep(.3);(dst/'new.txt').unlink();cli('status');wait(dst/'new.txt','added')
        cli('unwatch','--group','source',*common)
        cli('publish','--group','compiled',*common)
        (src/'new.txt').write_text('unfinished next build')
        # Receiver restart must restore the immutable last successful snapshot.
        receiver.terminate();receiver.wait(timeout=5);(dst/'new.txt').unlink();receiver=start_receiver();wait(dst/'new.txt','added')
        cli('build','--group','compiled',*common,'--','sh','-c','exit 9',ok=False)
        time.sleep(1.5);assert (dst/'new.txt').read_text()=='added'
        cli('build','--group','compiled',*common,'--','sh','-c','true');wait(dst/'new.txt','unfinished next build')
        print('PASS: automatic add/change/delete, daemon reuse/restart recovery, receiver replacement, stable build revision, failed/successful build')
    finally:
        cli('daemon','stop',ok=True)
        if receiver is not None:receiver.terminate();receiver.wait(timeout=5)
