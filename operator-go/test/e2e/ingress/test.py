#!/usr/bin/env python3
"""Real TLS Ingress path, no kubectl port-forward anywhere in this test."""
import datetime,hashlib,http.client,json,os,pathlib,ssl,subprocess,tempfile,time,urllib.request,urllib.error
from setup import NS,SYSTEM,STATE,SYNC,APP,BRIDGE,ROOT,K,kub
BIN=ROOT/'operator-go/bin/shadok';BASE=f'https://{SYNC}:8443';APP_URL=f'https://{APP}:8443';CA=STATE/'ca.crt'
def get(kind,name,ns=NS):return json.loads(kub('-n',ns,'get',kind,name,'-o','json'))
def wait(fn,label,seconds=90):
    end=time.monotonic()+seconds;last=''
    while time.monotonic()<end:
        try:
            result=fn()
            if result:return result
        except Exception as e:last=str(e)
        time.sleep(.25)
    raise AssertionError(label+': '+last)
identity=f'system:serviceaccount:{NS}:developer'
def toggle(enabled):return kub('-n',NS,'patch','developmentsession','ingress-live','--as',identity,'--type=merge','-p',json.dumps({'spec':{'enabled':enabled}}))
def main():
    since=datetime.datetime.now(datetime.timezone.utc).isoformat().replace('+00:00','Z')
    assert [n['metadata']['name'] for n in json.loads(kub('get','nodes','-o','json'))['items']]==['shadok-go-e2e-control-plane']
    tls=ssl.create_default_context(cafile=str(CA));opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),urllib.request.HTTPSHandler(context=tls))
    def request(url,data=None):
        try:
            with opener.open(urllib.request.Request(url,data=data),timeout=10) as response:return response.status,response.read()
        except urllib.error.HTTPError as e:return e.code,e.read()
    route=f'/{NS}/baseline'
    wait(lambda:request(BASE+route+'/plan',b'{}')[0]==409,'TLS Ingress route to inactive gateway')
    # The trust is explicit: the default system CA must not accept the test certificate.
    try:
        urllib.request.build_opener(urllib.request.ProxyHandler({})).open(BASE+route+'/plan',timeout=5)
        raise AssertionError('test certificate unexpectedly trusted without CA')
    except urllib.error.URLError as e:assert isinstance(e.reason,ssl.SSLCertVerificationError),e
    controller=get('deployment','shadok-ingress-traefik',SYSTEM)
    args=controller['spec']['template']['spec']['containers'][0]['args']
    for key,value in [('readtimeout','120s'),('writetimeout','120s'),('idletimeout','180s')]:assert any(f'websecure.transport.respondingtimeouts.{key}={value}' in arg.lower() for arg in args),(key,args)
    assert get('middleware','sync-upload')['spec']['buffering']['maxRequestBodyBytes']==570425344
    assert get('ingress','sync')['spec']['ingressClassName']=='shadok-local'
    assert not get('deployment','gateway')['spec']['template']['spec'].get('volumes'),'gateway should not mount TLS certificate'
    assert request(BASE+f'/{NS}/missing/plan',b'{}')[0]==409
    assert request(BASE+'/another-namespace/baseline/plan',b'{}')[0]==409
    assert request(BASE+'/__limit_probe',b'x'*512)[0]==404
    assert request(BASE+'/__limit_probe',b'x'*2048)[0]==413,'controller buffering limit was not applied'
    for verb,resource in [('get','pods'),('get','secrets'),('patch','deployments'),('create','pods/portforward')]:
        result=subprocess.run(K+['-n',NS,'auth','can-i',verb,resource,'--as',identity],capture_output=True,text=True);assert result.stdout.strip()=='no'
    original=get('deployment','baseline')['spec'];assert request(APP_URL+'/')[1]==b'baseline\n'
    previous={name:get('deployment',name,'shadok-live-e2e')['spec'] for name in ['baseline','node','python','ts','vite','spring']}
    with tempfile.TemporaryDirectory(prefix='shadok-ingress-client-') as td:
        work=pathlib.Path(td);source=work/'source';source.mkdir();(source/'index.html').write_text('via-real-ingress-v1\n');blob=os.urandom(2*1024*1024);(source/'large.bin').write_bytes(blob)
        config=work/'shadok.json';config.write_text(json.dumps({'version':1,'groups':{'live':{'mode':'watch','roots':[{'mount':'application','path':str(source)}]}}}))
        env=dict(os.environ,SHADOK_STATE_DIR=str(work/'daemon'),KUBECONFIG=str(work/'absent'),NO_PROXY=SYNC+','+APP,no_proxy=SYNC+','+APP)
        common=['--config',str(config),'--group','live','--url',BASE,'--namespace',NS,'--deployment','baseline','--ca-file',str(CA),'--timeout','90s']
        def cli(*args):return subprocess.check_output([str(BIN),*args],env=env,text=True,stderr=subprocess.STDOUT,timeout=110)
        started=False
        try:
            toggle(True);wait(lambda:get('deployment','baseline')['spec']['template']['metadata'].get('annotations',{}).get('shadok.org/live-session'),'live template')
            kub('-n',NS,'rollout','status','deployment/baseline','--timeout=90s')
            started=True;print(cli('watch',*common).strip(),flush=True)
            wait(lambda:request(APP_URL+'/')[1]==b'via-real-ingress-v1\n','initial revision via application Ingress')
            wait(lambda:hashlib.sha256(request(APP_URL+'/large.bin')[1]).digest()==hashlib.sha256(blob).digest(),'2 MiB payload through converged Ingress')
            (source/'index.html').write_text('via-real-ingress-v2\n');wait(lambda:request(APP_URL+'/')[1]==b'via-real-ingress-v2\n','automatic modification through ingress')
            manifest=json.loads(cli('status'))[0]['snapshot']['Manifest'];body=json.dumps(manifest).encode()
            # Wire-level slow body: the ingress must retain the route while receiving it.
            conn=http.client.HTTPSConnection(SYNC,8443,context=tls,timeout=10);conn.putrequest('POST',route+'/plan');conn.putheader('Content-Length',str(len(body)));conn.endheaders();split=len(body)//2;start=time.monotonic();conn.send(body[:split]);time.sleep(2);conn.send(body[split:]);response=conn.getresponse();assert response.status==200,response.read();response.read();conn.close();assert time.monotonic()-start>=2
            cli('unwatch',*common);toggle(False);wait(lambda:get('deployment','baseline')['spec']==original,'exact baseline restoration');kub('-n',NS,'rollout','status','deployment/baseline','--timeout=90s');wait(lambda:request(APP_URL+'/')[1]==b'baseline\n','baseline through application Ingress');assert request(BASE+route+'/plan',b'{}')[0]==409
            for name,spec in previous.items():assert get('deployment',name,'shadok-live-e2e')['spec']==spec,'existing fixture changed: '+name
            # Evidence from the actual controller, including path, router, status and body size.
            rows=[]
            for line in kub('-n',SYSTEM,'logs','deployment/shadok-ingress-traefik','--since-time='+since).splitlines():
                try:row=json.loads(line)
                except ValueError:continue
                if row.get('RequestHost','').split(':')[0]==SYNC:rows.append(row)
            assert any(row.get('RequestPath')==route+'/apply' and row.get('DownstreamStatus')==200 and row.get('RequestContentSize',0)>2*1024*1024 for row in rows),'missing controller upload evidence'
            assert any(row.get('RequestPath')=='/__limit_probe' and row.get('DownstreamStatus')==413 for row in rows),'missing controller limit evidence'
            evidence={'url':BASE+route,'application':APP_URL,'ingressClass':'shadok-local','controllerArgs':args,'accessLogs':rows,'uploadBytes':len(blob),'slowBodySeconds':2,'baselineRestored':True,'previousFixturesPreserved':True}
            (STATE/'evidence.json').write_text(json.dumps(evidence,indent=2))
            print('PASS: nip.io DNS -> loopback TCP -> Kind NodePort -> Traefik TLS Ingress -> HTTP gateway -> live receiver; 2 MiB upload, slow request, 413 threshold, routing isolation, CR-only identity, app modification, exact baseline restore. Evidence: '+str(STATE/'evidence.json'))
        finally:
            # Only this test's CR is restored, including on failure; no deletion of workloads.
            toggle(False)
            if started:cli('daemon','stop')
if __name__=='__main__':main()
