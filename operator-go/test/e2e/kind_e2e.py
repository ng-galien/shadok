#!/usr/bin/env python3
"""Existing Deployment -> live -> baseline, through the HTTPS gateway in dedicated Kind.
Build/load local images first. kubectl is used by this test administrator only.
"""
import argparse,json,os,pathlib,re,shutil,ssl,subprocess,tempfile,time,urllib.request,urllib.error
p=argparse.ArgumentParser();p.add_argument('--stack',choices=['baseline','node','python','spring','ts','vite'],default='baseline');args=p.parse_args()
ROOT=pathlib.Path(__file__).resolve().parents[3];BIN=pathlib.Path(os.environ.get('SHADOK_TEST_BINARY',str(ROOT/'operator-go/bin/shadok')));NS='shadok-live-e2e';SYSTEM='shadok-live-system'
CLUSTER=os.environ.get('SHADOK_TEST_CLUSTER','shadok-go-e2e')
assert CLUSTER in ('shadok-go-e2e','shadok-release-smoke'),'not a dedicated test cluster'
CHART=os.environ.get('SHADOK_TEST_CHART',str(ROOT/'operator-go/chart'))
RELEASE=os.environ.get('SHADOK_TEST_VERSION','')
K=['kubectl','--kubeconfig',f'/tmp/{CLUSTER}.kubeconfig','--context','kind-'+CLUSTER]
H=['helm','--kubeconfig',f'/tmp/{CLUSTER}.kubeconfig','--kube-context','kind-'+CLUSTER]
HE=dict(os.environ,HELM_CACHE_HOME='/tmp/shadok-helm-cache',HELM_CONFIG_HOME='/tmp/shadok-helm-config',HELM_DATA_HOME='/tmp/shadok-helm-data')
def kub(*a,input=None):return subprocess.check_output(K+list(a),input=input,text=True,stderr=subprocess.STDOUT)
def apply(obj):return kub('apply','-f','-',input=json.dumps(obj))
def get(kind,name,ns=NS):return json.loads(kub('-n',ns,'get',kind,*([name] if name else []),'-o','json'))
def wait(fn,description,seconds=120):
    deadline=time.monotonic()+seconds;last=''
    while time.monotonic()<deadline:
        try:
            value=fn()
            if value:return value
        except Exception as e:last=str(e)
        time.sleep(.5)
    raise AssertionError(description+': '+last)
assert [x['metadata']['name'] for x in json.loads(kub('get','nodes','-o','json'))['items']]==[CLUSTER+'-control-plane'],'wrong cluster'
for ns in [NS,SYSTEM]:apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':ns}})
# Existing older CRD in this reused development cluster: Helm deliberately does not upgrade CRDs.
if not RELEASE:kub('apply','-f',str(ROOT/'operator-go/chart/crds/shadok.org_developmentsessions.yaml'))
else:
    assert args.stack=='baseline','release smoke targets baseline'
    assert subprocess.check_output([str(BIN),'--version'],text=True).strip()==RELEASE
    subprocess.run(H+['upgrade','--install','runtime',CHART,'--version',RELEASE,'-n',SYSTEM,'--create-namespace','--wait','--timeout','300s'],env=HE,check=True)
apply({'apiVersion':'v1','kind':'ServiceAccount','metadata':{'name':'developer','namespace':NS}})
kub('-n',NS,'apply','-f',str(ROOT/'operator-go/config/developer-role.yaml'))
apply({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'RoleBinding','metadata':{'name':'developer','namespace':NS},'roleRef':{'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':'shadok-developer'},'subjects':[{'kind':'ServiceAccount','name':'developer','namespace':NS}]})
identity='system:serviceaccount:'+NS+':developer'
for verb,resource in [('get','secrets'),('get','pods'),('patch','deployments'),('create','pods/portforward')]:
    result=subprocess.run(K+['-n',NS,'auth','can-i',verb,resource,'--as',identity],text=True,capture_output=True)
    assert result.stdout.strip()=='no',(verb,resource,result.stdout)
def toggle(enabled):return kub('-n',NS,'patch','developmentsession',session_name,'--type=merge','-p',json.dumps({'spec':{'enabled':enabled}}),'--as',identity)
stack=args.stack;name=stack;session_name=name+'-live' if stack=='spring' else name;port={'baseline':8080,'node':3000,'python':8000,'spring':8080,'ts':8080,'vite':8080}[stack]
mount='classes' if stack=='spring' else 'application'
image_path={'baseline':'/app','node':'/app/src','python':'/app/src','spring':'/tmp','ts':'/app/dist','vite':'/app/src'}[stack]
commands={'baseline':['python','-m','http.server','8080','--directory','/app'],'node':['./node_modules/.bin/nodemon','--legacy-watch','src/app.js'],'python':['python','-m','uvicorn','main:app','--host','0.0.0.0','--port','8000','--reload','--reload-dir','/app/src'],'spring':['java','-cp','/live/classes:/live/packaged/unpacked/BOOT-INF/lib/*:/app/lib/*:/opt/devtools/*','example.Application'],'ts':['node','--watch','dist/server.js'],'vite':['./node_modules/.bin/vite','--host','0.0.0.0','--port','8080']}
# A platform-owned Deployment exists before the Shadok release; no generated dev Deployment.
d={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':name,'namespace':NS},'spec':{'replicas':2 if stack=='baseline' else 1,'selector':{'matchLabels':{'app':name}},'template':{'metadata':{'labels':{'app':name},'annotations':{'platform.example/retained':'yes'}},'spec':{'containers':[{'name':'app','image':f'shadok-{stack}:local','imagePullPolicy':'IfNotPresent','env':[{'name':'PLATFORM_VALUE','value':'preserved'}],'resources':{'requests':{'cpu':'10m','memory':'32Mi'},'limits':{'memory':'512Mi' if stack=='spring' else '256Mi'}}}]}}}}
try:
    get('developmentsession',session_name)
except subprocess.CalledProcessError:pass
else:
    toggle(False)
    wait(lambda:not get('deployment',name)['spec']['template']['metadata'].get('annotations',{}).get('shadok.org/live-session'),'cleanup previous live test')
d['spec']['template']['spec']['containers'][0]['readinessProbe']={'httpGet':{'path':'/' if stack in ('baseline','vite') else '/hello','port':port},'initialDelaySeconds':3,'periodSeconds':1}
apply(d);apply({'apiVersion':'v1','kind':'Service','metadata':{'name':name,'namespace':NS},'spec':{'selector':{'app':name},'ports':[{'port':port,'targetPort':port}]}})
if stack=='spring':kub('-n',NS,'rollout','restart','deployment/'+name)
kub('-n',NS,'rollout','status','deployment/'+name,'--timeout=120s');original=get('deployment',name)['spec']
if stack=='spring':
    baseline_pod=next(x for x in get('pods','')['items'] if x['metadata'].get('labels',{}).get('app')==name and not x['metadata'].get('deletionTimestamp'))
    baseline_logs=kub('-n',NS,'logs',baseline_pod['metadata']['name'],'-c','app')
    baseline_files=kub('-n',NS,'exec',baseline_pod['metadata']['name'],'-c','app','--','ls','-A','/app').splitlines()
    assert baseline_files==['application.jar','lib'],'production /app must use the efficient layered JAR layout'
    import zipfile
    with zipfile.ZipFile(ROOT/'pods/spring-hello/target/spring-hello-0.1.0.jar') as jar:
        assert not any('spring-boot-devtools' in name for name in jar.namelist()),'DevTools packaged in production jar'
        assert 'BOOT-INF/classes/example/Application.class' in jar.namelist()
    cmdline=kub('-n',NS,'exec',baseline_pod['metadata']['name'],'-c','app','--','cat','/proc/1/cmdline')
    assert cmdline.split('\x00')[:3]==['java','-jar','/app/application.jar'],'baseline is not java -jar'
    assert 'restartedMain' not in baseline_logs,'baseline loaded DevTools'
    baseline_image_id=next(c['imageID'] for c in baseline_pod['status']['containerStatuses'] if c['name']=='app')
    assert not any(m['mountPath']=='/opt/devtools' for m in baseline_pod['spec']['containers'][0].get('volumeMounts',[])), 'production must not have a preinstalled tools mount'
    print('PASS Spring production baseline: java -jar, layered application JAR and lib directory, no packaged DevTools and no tools mount',flush=True)
with tempfile.TemporaryDirectory(prefix=f'shadok-live-{stack}-') as td:
    base=pathlib.Path(td);src=base/'src';src.mkdir();forwards=[]
    # Self-signed TLS is scoped to this isolated test; the client validates it explicitly.
    cert=base/'ca.crt';key=base/'tls.key'
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(key),'-out',str(cert),'-days','1','-subj','/CN=localhost','-addext','subjectAltName=DNS:localhost'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    secret=json.loads(kub('-n',SYSTEM,'create','secret','tls','gateway-tls','--cert',str(cert),'--key',str(key),'--dry-run=client','-o','json'));apply(secret)
    values={'operator':{'image':{'tag':'local'},'toolImage':{'tag':'local'}},'gateway':{'image':{'tag':'local'},'tlsSecretName':'gateway-tls'},'session':{'create':True,'namespace':NS,'name':session_name,'enabled':False,'deployment':name,'container':'app','runAsUser':1000,'runAsGroup':1000,'directories':[{'name':mount,'imagePath':image_path,'mountPath':'/live/classes' if stack=='spring' else image_path}],'start':{'command':commands[stack][:1],'args':commands[stack][1:],'workingDir':'/app'}}}
    if RELEASE:
        values['operator']={}
        values['gateway'].pop('image')
        values['service']={'type':'NodePort','nodePort':30443}
    if stack=='spring':
        spring_spec=json.loads(kub('create','--dry-run=client','-f',str(ROOT/'pods/spring-hello/kubernetes/session.yaml'),'-o','json'))['spec']
        values['session']['image']=''
        values['session']['directories']=spring_spec['directories']
        values['session']['init']=spring_spec['init']
        values['session']['volumes']=spring_spec['volumes']
    # One infrastructure release, then instance-only releases for additional targets.
    if stack!='baseline':values['operator']={'enabled':False}
    vf=base/'values.json';vf.write_text(json.dumps(values));release='runtime' if stack=='baseline' else stack
    subprocess.run(H+['upgrade','--install',release,CHART,*(['--version',RELEASE] if RELEASE else []),'-n',SYSTEM,'-f',str(vf),'--wait','--timeout','120s'],env=HE,check=True)
    # Refresh TLS after a test has renewed the certificate.
    kub('-n',SYSTEM,'rollout','restart','deployment/runtime-shadok-gateway');kub('-n',SYSTEM,'rollout','status','deployment/runtime-shadok-gateway','--timeout=120s')
    def forward(ns,target,remote):
        if RELEASE:
            if ns==SYSTEM:return 18443
            kub('-n',ns,'patch',target,'--type=merge','-p',json.dumps({'spec':{'type':'NodePort','ports':[{'port':remote,'targetPort':remote,'nodePort':30081}]}}))
            return 18081
        if ns==SYSTEM and target=='service/runtime-shadok':
            # Port-forward the live gateway pod, not a terminating replica selected from the Service.
            selector=get('deployment','runtime-shadok-gateway',SYSTEM)['spec']['selector']['matchLabels']
            candidates=[p for p in get('pods','',SYSTEM)['items'] if all(p['metadata'].get('labels',{}).get(k)==v for k,v in selector.items()) and not p['metadata'].get('deletionTimestamp') and any(c.get('type')=='Ready' and c.get('status')=='True' for c in p.get('status',{}).get('conditions',[]))]
            assert len(candidates)==1, 'expected one ready runtime gateway pod'
            target_port=next(p['targetPort'] for p in get('service','runtime-shadok',SYSTEM)['spec']['ports'] if p['port']==remote)
            remote=target_port if isinstance(target_port,int) else next(p['containerPort'] for c in candidates[0]['spec']['containers'] for p in c.get('ports',[]) if p['name']==target_port)
            target='pod/'+candidates[0]['metadata']['name']
        proc=subprocess.Popen(K+['-n',ns,'port-forward','--address=127.0.0.1',target,f':{remote}'],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True);forwards.append(proc)
        line=proc.stdout.readline();m=re.search(r'127.0.0.1:(\d+)',line);assert m,(line,proc.stderr.read());return int(m.group(1))
    gateway='https://localhost:'+str(forward(SYSTEM,'service/runtime-shadok',80));tls=ssl.create_default_context(cafile=str(cert))
    def unavailable(path):
        global gateway
        try:urllib.request.urlopen(urllib.request.Request(gateway+path+'/plan',b'{}'),context=tls,timeout=5)
        except urllib.error.HTTPError as e:return e.code in (404,409)
        except (urllib.error.URLError,TimeoutError,ConnectionError):
            gateway='https://localhost:'+str(forward(SYSTEM,'service/runtime-shadok',80))
            return False
        return False
    for path in ('/'+NS+'/'+name,'/'+NS+'/absent','/other-namespace/'+name):
        wait(lambda:unavailable(path),'gateway must reject inactive/missing/cross-namespace target '+path)
    # Only the CR is changed by the developer operation.
    toggle(True)
    wait(lambda:get('deployment',name)['spec']['template']['metadata'].get('annotations',{}).get('shadok.org/live-session'),'live transformation')
    kub('-n',NS,'rollout','status','deployment/'+name,'--timeout=120s')
    live=get('deployment',name)['spec'];assert live['replicas']==original['replicas'];assert live['template']['metadata']['labels']['app']==name
    assert live['template']['spec']['containers'][0]['env']==original['template']['spec']['containers'][0]['env']
    def pods():return [x for x in get('pods','')['items'] if x['metadata'].get('labels',{}).get('app')==name and not x['metadata'].get('deletionTimestamp')]
    if stack=='spring':
        live_pod=pods()[0]
        assert live['template']['spec']['containers'][0]['image']==original['template']['spec']['containers'][0]['image'],'application image changed'
        assert next(c['imageID'] for c in live_pod['status']['containerStatuses'] if c['name']=='app')==baseline_image_id,'application image digest changed'
        mounts=live['template']['spec']['containers'][0]['volumeMounts']
        assert any(m['mountPath']=='/opt/devtools' and m.get('readOnly') for m in mounts),'DevTools not read-only'
        init_status=next(c for c in live_pod['status']['initContainerStatuses'] if c['name']=='shadok-init-unpack')
        assert init_status['state']['terminated']['exitCode']==0,'JDK initialization did not complete'
        print('PASS Spring live activation: same production image digest, JAR extracted inside Pod by standard JDK init, DevTools automatically downloaded and verified into a read-only app mount',flush=True)
    if stack!='baseline':
        demo=ROOT/f'pods/{stack}-hello'
        if stack in ('spring','ts'):
            work=base/'project';shutil.copytree(demo,work,ignore=shutil.ignore_patterns('node_modules','target','dist','shadok.yaml'))
            if stack=='ts':os.symlink(demo/'node_modules',work/'node_modules')
            src=work/('target/classes' if stack=='spring' else 'dist');subprocess.run(['mvn','-q','compile'] if stack=='spring' else ['npm','run','build'],cwd=work,check=True)
        else:shutil.copytree(demo/'src',src,dirs_exist_ok=True)
    else:(src/'index.html').write_text('synchronized-v1\n')
    config=base/'config.json'
    if stack!='spring':config.write_text(json.dumps({'version':1,'groups':{'live':{'mode':'build' if RELEASE or stack in ('spring','ts') else 'watch','roots':[{'mount':mount,'path':str(src),'exclude':['**/__pycache__/**','**/*.pyc']}]}}}))
    # Daemon cannot obtain Kubernetes credentials from its environment.
    env=dict(os.environ,SHADOK_STATE_DIR=str(base/'daemon'),KUBECONFIG=str(base/'does-not-exist'))
    common=['--config',str(config),'--group','live','--url',gateway,'--namespace',NS,'--deployment',name,'--ca-file',str(cert),'--timeout','90s']
    if stack=='spring':
        common=['--session',NS+'/'+session_name,'--url',gateway,'--ca-file',str(cert),'--timeout','90s']
        assert not (work/'shadok.yaml').exists() and not config.exists(),'session sync must not need local configuration'
        print('PASS session-name sync: spring-live targets Deployment spring, no local sync configuration, no Kubernetes credentials',flush=True)
    def cli(*a,ok=True):
        result=subprocess.run([str(BIN),*a],env=env,cwd=work if stack=='spring' else None,text=True,capture_output=True,timeout=110)
        if ok and result.returncode:
            status=subprocess.run([str(BIN),'status',*common],env=env,text=True,capture_output=True,timeout=10)
            raise AssertionError(result.stdout+result.stderr+'\nDaemon status: '+status.stdout+status.stderr)
        if not ok and result.returncode==0:raise AssertionError('failed build accepted')
        return result.stdout
    app_url='http://127.0.0.1:'+str(forward(NS,'service/'+name,port));route='/src/main.js' if stack=='vite' else ('/' if stack=='baseline' else '/hello')
    def expect(text):
        def attempt():
            global app_url
            try:return text in urllib.request.urlopen(app_url+route,timeout=2).read().decode()
            except Exception:
                app_url='http://127.0.0.1:'+str(forward(NS,'service/'+name,port));return False
        wait(attempt,'application response '+text,120)
    try:
        if stack=='baseline':expect('baseline')
        print(cli('publish' if RELEASE or stack in ('spring','ts') else 'watch',*common).strip(),flush=True)
        if stack=='baseline':
            expect('synchronized-v1');(src/'index.html').write_text('synchronized-v2\n');expected='synchronized-v2'
            if RELEASE:
                cli('build',*common,'--','sh','-c','exit 9',ok=False)
                expect('synchronized-v1')
                cli('build',*common,'--','sh','-c','exit 0')
                print('PASS release build hook: failed build retained v1; successful build acknowledged v2',flush=True)
        elif stack in ('spring','ts'):
            f=work/('src/main/java/example/Application.java' if stack=='spring' else 'src/server.ts');f.write_text(f.read_text().replace(stack+'-baseline','shadok-live-change'))
            cli('build',*common,'--','sh','-c','exit 9',ok=False)
            subprocess.run([str(BIN),'build',*common,'--',*(['mvn','-q','compile'] if stack=='spring' else ['npm','run','build'])],cwd=work,env=env,check=True);expected='shadok-live-change'
        elif stack=='vite':f=src/'main.js';f.write_text(f.read_text().replace('vite-baseline','shadok-live-change'));expected='shadok-live-change'
        else:
            f=src/('app.js' if stack=='node' else 'main.py');old='Hello World from Node.js Express server! 🚀' if stack=='node' else 'Hello World from Python Pod!';f.write_text(f.read_text().replace(old,'shadok-live-change'));expected='shadok-live-change'
        expect(expected)
        if stack=='spring':
            before=pods()[0]
            def app_identity(pod):
                status=next(c for c in pod['status']['containerStatuses'] if c['name']=='app')
                return pod['metadata']['uid'],status['containerID'],status['restartCount']
            before_identity=app_identity(before)
            def response(path):
                global app_url
                try:
                    with urllib.request.urlopen(app_url+path,timeout=5) as r:return r.status,r.read()
                except urllib.error.HTTPError as e:return e.code,e.read()
                except (urllib.error.URLError,TimeoutError,ConnectionError):
                    app_url='http://127.0.0.1:'+str(forward(NS,'service/'+name,port))
                    return None,b''
            new_route='/added-controller'
            def absent(path):
                try:
                    urllib.request.urlopen(app_url+path,timeout=5)
                    raise AssertionError('route already exists: '+path)
                except urllib.error.HTTPError as e:assert e.code==404,e
            absent('/added-method')
            application=work/'src/main/java/example/Application.java'
            text=application.read_text();pos=text.rfind('}')
            application.write_text(text[:pos]+'@GetMapping("/added-method") public String added() { return "new-method-live"; }\n'+text[pos:])
            subprocess.run([str(BIN),'build',*common,'--','mvn','-q','compile'],cwd=work,env=env,check=True)
            wait(lambda:response('/added-method')==(200,b'new-method-live'),'added method registered by DevTools')
            assert app_identity(pods()[0])==before_identity,'method addition restarted/replaced container'
            print('PASS Spring DevTools: added controller method 404 -> 200; same Pod and container',flush=True)
            try:
                urllib.request.urlopen(app_url+new_route,timeout=5)
                raise AssertionError('new controller route already exists')
            except urllib.error.HTTPError as e:
                assert e.code==404,e
            controller=work/'src/main/java/example/AddedController.java'
            controller.write_text('package example;\nimport org.springframework.web.bind.annotation.*;\n@RestController\npublic class AddedController {\n@GetMapping("/added-controller") public String hello() { return "new-controller-live"; }\n}\n')
            subprocess.run([str(BIN),'build',*common,'--','mvn','-q','compile'],cwd=work,env=env,check=True)
            def added_controller():
                return response(new_route)==(200,b'new-controller-live')
            wait(added_controller,'new Spring controller discovered by DevTools')
            assert app_identity(pods()[0])==before_identity,'Spring controller addition restarted/replaced the container'
            logs=kub('-n',NS,'logs',before['metadata']['name'],'-c','app')
            assert 'Restarting due to' in logs and 'restartedMain' in logs,'DevTools restart not observed'
            print('PASS Spring DevTools: new @RestController route 404 -> 200 after build/sync; same Pod UID, container ID and restart count; DevTools restart logged',flush=True)
            controller.unlink()
            subprocess.run([str(BIN),'build',*common,'--','mvn','-q','clean','compile'],cwd=work,env=env,check=True)
            def removed_controller():
                return response(new_route)[0]==404
            wait(removed_controller,'deleted controller route removed by DevTools')
            kub('-n',NS,'exec',before['metadata']['name'],'-c','app','--','test','!','-e','/live/classes/example/AddedController.class')
            assert app_identity(pods()[0])==before_identity,'controller deletion restarted/replaced container'
            wait(lambda:response('/added-method')==(200,b'new-method-live'),'remaining route preserved')
            print('PASS Spring DevTools: deleted controller .class absent in Pod, route 200 -> 404; remaining method still responds; same Pod and container',flush=True)
        if stack=='baseline':
            (src/'added.txt').write_text('added')
            if RELEASE:cli('publish',*common)
            wait(lambda:urllib.request.urlopen(app_url+'/added.txt',timeout=2).read()==b'added','addition')
            (src/'added.txt').unlink()
            if RELEASE:cli('publish',*common)
            def deleted():
                try:urllib.request.urlopen(app_url+'/added.txt',timeout=2)
                except urllib.error.HTTPError as e:return e.code==404
                return False
            wait(deleted,'deletion')
            for pod in pods():
                content=kub('-n',NS,'exec',pod['metadata']['name'],'-c','app','--','cat','/app/index.html');assert expected in content,'replica missed revision'
        old=pods()[0];kub('-n',NS,'delete','pod',old['metadata']['name'],'--wait=false')
        wait(lambda:len(pods())==original['replicas'] and all(x['metadata']['uid']!=old['metadata']['uid'] and all(c.get('ready') for c in x.get('status',{}).get('containerStatuses',[{}])) for x in pods()),'replacement Pod ready')
        expect(expected)
        if stack=='baseline':
            wait(lambda:all(expected in kub('-n',NS,'exec',pod['metadata']['name'],'-c','app','--','cat','/app/index.html') for pod in pods()),'replacement replica synchronized')
        cli('unwatch',*common)
        toggle(False)
        wait(lambda:get('deployment',name)['spec']==original,'exact baseline restoration')
        kub('-n',NS,'rollout','status','deployment/'+name,'--timeout=120s')
        wait(lambda:unavailable('/'+NS+'/'+name),'disabled route must be rejected')
        print(f'PASS {stack}: Helm instance, HTTPS route, inactive/missing/isolation, live response, replacement, exact baseline restoration',flush=True)
    finally:
        # Restore the fixture even when synchronization or assertions fail.
        toggle(False)
        wait(lambda:get('deployment',name)['spec']==original,'cleanup baseline restoration')
        cli('daemon','stop')
        for proc in forwards:
            if proc.poll() is None:proc.terminate()
        for proc in forwards:
            try:proc.wait(timeout=5)
            except subprocess.TimeoutExpired:proc.kill()
