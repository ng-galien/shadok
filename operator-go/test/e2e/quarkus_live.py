#!/usr/bin/env python3
"""Fast-jar production baseline + framework-only reload tools, tested through Shadok.
Dedicated Kind only. App JAR/classes always originate from shadok-quarkus:local.
The mutable build is used solely to obtain matching Quarkus deployment tooling.
"""
import base64, hashlib, json, os, pathlib, re, shutil, subprocess, tempfile, time, urllib.error, urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[3];PROJECT=ROOT/'pods/quarkus-hello';BIN=ROOT/'operator-go/bin/shadok'
K=['kubectl','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--context','kind-shadok-go-e2e'];NS='shadok-quarkus-e2e';SYSTEM='shadok-live-system';NAME='quarkus'
def kub(*a,input=None):return subprocess.check_output(K+list(a),input=input,text=True,stderr=subprocess.STDOUT)
def apply(x):return kub('apply','-f','-',input=json.dumps(x))
def get(kind,name,ns=NS):return json.loads(kub('-n',ns,'get',kind,*([name] if name else []),'-o','json'))
def wait(fn,label,seconds=180):
 end=time.monotonic()+seconds;last=''
 while time.monotonic()<end:
  try:
   result=fn()
   if result:return result
  except Exception as e:last=str(e)
  time.sleep(1)
 raise AssertionError(label+': '+last)
def pods():return [p for p in get('pods','')['items'] if p['metadata'].get('labels',{}).get('app')==NAME and not p['metadata'].get('deletionTimestamp')]
def identity():
 p=pods()[0];s=next(c for c in p['status']['containerStatuses'] if c['name']=='app')
 return (p['metadata']['uid'],s['containerID'],s['restartCount'],s['imageID'])
assert [n['metadata']['name'] for n in json.loads(kub('get','nodes','-o','json'))['items']]==['shadok-go-e2e-control-plane']
apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':NS}})
try:get('developmentsession',NAME)
except subprocess.CalledProcessError:pass
else:
 kub('-n',NS,'patch','developmentsession',NAME,'--type=merge','-p','{"spec":{"enabled":false}}')
 wait(lambda:not get('deployment',NAME)['spec']['template']['metadata'].get('annotations',{}).get('shadok.org/live-session'),'previous restoration')
with tempfile.TemporaryDirectory(prefix='shadok-quarkus-framework-') as td:
 base=pathlib.Path(td);kit=base/'kit';mutable=PROJECT/'build/quarkus-app'
 shutil.copytree(mutable/'lib/deployment',kit/'lib/deployment');(kit/'quarkus').mkdir()
 shutil.copy2(mutable/'quarkus/build-system.properties',kit/'quarkus/build-system.properties')
 assert not (kit/'app').exists() and not (kit/'dev').exists() and not (kit/'quarkus-run.jar').exists()
 for p in kit.rglob('*'):
  if p.is_file():assert 'quarkus-hello' not in p.name,'application artifact entered tooling bundle'
 apply({'apiVersion':'v1','kind':'PersistentVolumeClaim','metadata':{'name':'reload-tools','namespace':NS},'spec':{'accessModes':['ReadWriteOnce'],'resources':{'requests':{'storage':'256Mi'}}}})
 kub('-n',NS,'delete','pod','reload-tools-loader','--ignore-not-found')
 apply({'apiVersion':'v1','kind':'Pod','metadata':{'name':'reload-tools-loader','namespace':NS},'spec':{'securityContext':{'runAsUser':185,'runAsGroup':185,'fsGroup':185},'containers':[{'name':'loader','image':'shadok-quarkus:local','imagePullPolicy':'Never','command':['sh','-c','sleep 3600'],'volumeMounts':[{'name':'tools','mountPath':'/tools'}]}],'volumes':[{'name':'tools','persistentVolumeClaim':{'claimName':'reload-tools'}}]}})
 kub('-n',NS,'wait','--for=condition=Ready','pod/reload-tools-loader','--timeout=120s')
 kub('-n',NS,'cp',str(kit)+'/.','reload-tools-loader:/tools')
 kub('-n',NS,'delete','pod','reload-tools-loader','--wait=true')
 d={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':NAME,'namespace':NS},'spec':{'replicas':1,'selector':{'matchLabels':{'app':NAME}},'template':{'metadata':{'labels':{'app':NAME},'annotations':{'platform.example/preserved':'yes'}},'spec':{'securityContext':{'fsGroup':185},'containers':[{'name':'app','image':'shadok-quarkus:local','imagePullPolicy':'Never','env':[{'name':'PLATFORM_VALUE','value':'preserved'}],'resources':{'requests':{'memory':'128Mi','cpu':'100m'},'limits':{'memory':'1Gi'}},'readinessProbe':{'httpGet':{'path':'/hello','port':8080},'periodSeconds':2},'volumeMounts':[{'name':'tools','mountPath':'/opt/quarkus-reload','readOnly':True}]}],'volumes':[{'name':'tools','persistentVolumeClaim':{'claimName':'reload-tools','readOnly':True}}]}}}}
 apply(d);apply({'apiVersion':'v1','kind':'Service','metadata':{'name':NAME,'namespace':NS},'spec':{'selector':{'app':NAME},'ports':[{'port':8080,'targetPort':8080}]}})
 kub('-n',NS,'rollout','status','deployment/'+NAME,'--timeout=180s');original=get('deployment',NAME)['spec'];production=identity()
 p=pods()[0]['metadata']['name'];logs=kub('-n',NS,'logs',p,'-c','app');assert 'Profile prod activated' in logs and 'Live Coding activated' not in logs
 kub('-n',NS,'exec',p,'-c','app','--','test','!','-e','/deployments/lib/deployment')
 app_hash=kub('-n',NS,'exec',p,'-c','app','--','sha256sum','/deployments/app/quarkus-hello-1.0.0-SNAPSHOT.jar').split()[0]
 print('PASS real fast-jar production image; no deployment tooling in /deployments; only framework resources in external volume',flush=True)
 env=dict(os.environ,SHADOK_STATE_DIR=str(base/'daemon'),KUBECONFIG=str(base/'no-kubeconfig'));forwards=[]
 def forward(ns,service,port):
  p=subprocess.Popen(K+['-n',ns,'port-forward','service/'+service,':'+str(port)],text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE);forwards.append(p)
  line=p.stdout.readline();m=re.search(r'127.0.0.1:(\d+)',line);assert m,line;return int(m.group(1))
 ca=base/'ca.crt';ca.write_bytes(base64.b64decode(get('secret','gateway-tls',SYSTEM)['data']['tls.crt']))
 gateway='https://localhost:'+str(forward(SYSTEM,'runtime-shadok',80))
 work=base/'project';shutil.copytree(PROJECT,work,ignore=shutil.ignore_patterns('build','.gradle','target'))
 common=['--config',str(work/'shadok.yaml'),'--group','quarkus-outputs','--url',gateway,'--namespace',NS,'--deployment',NAME,'--ca-file',str(ca),'--timeout','120s']
 def publish(clean=False):
  command=[str(work/'gradlew'),'--no-daemon',*(['clean'] if clean else []),'stageShadok','-Dquarkus.container-image.build=false']
  subprocess.run([str(BIN),'build',*common,'--',*command],cwd=work,env=env,check=True)
 session={'apiVersion':'shadok.org/v1alpha1','kind':'DevelopmentSession','metadata':{'name':NAME,'namespace':NS},'spec':{'enabled':True,'deployment':NAME,'container':'app','runAsUser':185,'runAsGroup':185,'directories':[{'name':'application','imagePath':'/deployments','mountPath':'/live/quarkus'}],'start':{'command':['sh'],'args':['-ec','cp -R /opt/quarkus-reload/lib/deployment /live/quarkus/lib/\ncp /opt/quarkus-reload/quarkus/build-system.properties /live/quarkus/quarkus/\nexport QUARKUS_LAUNCH_DEVMODE=true\nexec java -Dquarkus.http.host=0.0.0.0 -Dquarkus.profile=prod -Dquarkus.console.enabled=false -jar /live/quarkus/quarkus-run.jar'],'workingDir':'/live/quarkus'}}}
 try:
  apply(session);wait(lambda:get('deployment',NAME)['spec']['template']['metadata'].get('annotations',{}).get('shadok.org/live-session'),'live activation');kub('-n',NS,'rollout','status','deployment/'+NAME,'--timeout=180s')
  live=identity();assert live[3]==production[3];p=pods()[0]['metadata']['name']
  assert kub('-n',NS,'exec',p,'-c','app','--','sha256sum','/live/quarkus/app/quarkus-hello-1.0.0-SNAPSHOT.jar').split()[0]==app_hash
  assert 'Live Coding activated' in kub('-n',NS,'logs',p,'-c','app')
  app_url='http://127.0.0.1:'+str(forward(NS,NAME,8080))
  def response(path):
   try:
    with urllib.request.urlopen(app_url+path,timeout=10) as r:return r.status,r.read().decode()
   except urllib.error.HTTPError as e:return e.code,e.read().decode()
  assert response('/hello')[0]==200
  print('PASS live bootstrap: original production image AND application JAR checksum retained; framework-only tools; live coding active',flush=True)
  publish();resource=work/'src/main/java/com/shadok/pods/quarkus/HelloWorldResource.java';baseline=resource.read_text()
  assert response('/hello/added')[0]==404
  resource.write_text(baseline.replace('public class HelloWorldResource {','public class HelloWorldResource {\n @GET @Path("/added") public String added(){return "added-method";}'))
  publish();wait(lambda:response('/hello/added')==(200,'added-method'),'method added');assert identity()==live
  print('PASS added method: 404 -> 200; same pod/container',flush=True)
  added=resource.parent/'AddedResource.java';assert response('/added-resource')[0]==404
  added.write_text('package com.shadok.pods.quarkus; import jakarta.ws.rs.*; @Path("/added-resource") public class AddedResource { @GET public String get(){return "added-resource";} }')
  publish();wait(lambda:response('/added-resource')==(200,'added-resource'),'class added');assert identity()==live
  print('PASS added REST class: 404 -> 200; same pod/container',flush=True)
  added.unlink();resource.write_text(baseline);publish(clean=True)
  wait(lambda:response('/added-resource')[0]==404 and response('/hello/added')[0]==404,'deletions');assert identity()==live and response('/hello')[0]==200
  kub('-n',NS,'exec',p,'-c','app','--','test','!','-e','/live/quarkus/dev/app/com/shadok/pods/quarkus/AddedResource.class')
  print('PASS class/method removals: 200 -> 404; deleted class absent; baseline endpoint retained; same pod/container/restart count',flush=True)
  print('IDENTITY '+json.dumps(live),flush=True)
 finally:
  kub('-n',NS,'patch','developmentsession',NAME,'--type=merge','-p','{"spec":{"enabled":false}}');wait(lambda:get('deployment',NAME)['spec']==original,'restore');kub('-n',NS,'rollout','status','deployment/'+NAME,'--timeout=180s')
  subprocess.run([str(BIN),'daemon','stop'],env=env)
  for p in forwards:p.terminate();p.wait(timeout=10)
 logs=kub('-n',NS,'logs',pods()[0]['metadata']['name'],'-c','app');assert 'Live Coding activated' not in logs and identity()[3]==production[3]
 print('PASS exact production restoration',flush=True)
