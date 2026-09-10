#!/usr/bin/env python3
"""Execute Maven/npm hooks against a local receiver, without cluster credentials."""
import json,os,pathlib,socket,subprocess,tempfile,time
ROOT=pathlib.Path(__file__).resolve().parents[3];BIN=ROOT/'operator-go/bin/shadok'
with tempfile.TemporaryDirectory(prefix='shadok-hooks-') as td:
    base=pathlib.Path(td);roots={name:str(base/name) for name in ['classes','application']}
    for root in roots.values():pathlib.Path(root).mkdir()
    sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
    destinations=base/'destinations.json';destinations.write_text(json.dumps({'version':1,'destinations':{'local':{'url':f'http://127.0.0.1:{port}'}}}))
    env=dict(os.environ,PATH=str(BIN.parent)+os.pathsep+os.environ['PATH'],SHADOK_STATE_DIR=str(base/'daemon'),SHADOK_DESTINATIONS=str(destinations),SHADOK_DESTINATION='local',KUBECONFIG=str(base/'absent'))
    receiver=subprocess.Popen([str(BIN),'receive','--listen',f'127.0.0.1:{port}','--roots',json.dumps(roots)],stdout=subprocess.DEVNULL)
    try:
        subprocess.run(['npm','run','build:cluster'],cwd=ROOT/'pods/ts-hello',env=env,check=True)
        assert (base/'application/server.js').is_file()
        subprocess.run(['mvn','-q','-Pshadok','verify'],cwd=ROOT/'pods/spring-hello',env=env,check=True)
        assert (base/'classes/example/Application.class').is_file()
        print('PASS: actual npm build:cluster and Maven -Pshadok verify hooks acknowledged their compiled outputs')
    finally:
        subprocess.run([str(BIN),'daemon','stop'],env=env,stdout=subprocess.DEVNULL)
        receiver.terminate();receiver.wait(timeout=5)
