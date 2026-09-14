#!/usr/bin/env python3
"""Real CRD strategic patch lifecycle on the dedicated development Kind cluster."""
import json, subprocess, time
K=['kubectl','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--context','kind-shadok-go-e2e']
NS='shadok-patch-e2e'
def kub(*args):return subprocess.check_output(K+list(args),text=True,stderr=subprocess.STDOUT)
def apply(obj):
    obj=json.loads(json.dumps(obj))
    if isinstance(obj.get("spec",{}).get("podTemplatePatch"),dict):obj["spec"]["podTemplatePatch"]=json.dumps(obj["spec"]["podTemplatePatch"])
    return subprocess.run(K+['apply','-f','-'],input=json.dumps(obj),text=True,check=True,capture_output=True)
def get(kind,name):return json.loads(kub('-n',NS,'get',kind,*([name] if name else []),'-o','json'))
def wait(fn):
    deadline=time.monotonic()+120
    while time.monotonic()<deadline:
        if fn():return
        time.sleep(.5)
    raise AssertionError('condition did not converge')
def rollout():kub('-n',NS,'rollout','status','deployment/app','--timeout=120s')
def pod():return next(p for p in get('pods','')['items'] if not p['metadata'].get('deletionTimestamp') and all(c.get('ready') for c in p.get('status',{}).get('containerStatuses',[{}])))
apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':NS}})
command=['sh','-c','touch /tmp/healthy; exec python -m http.server 8080 --directory /app']
apply({'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':'app','namespace':NS},'spec':{'replicas':1,'selector':{'matchLabels':{'app':'patch-test'}},'template':{'metadata':{'labels':{'app':'patch-test'}},'spec':{'containers':[{'name':'app','image':'shadok-baseline:local','imagePullPolicy':'IfNotPresent','command':command,'resources':{'requests':{'cpu':'10m','memory':'32Mi'},'limits':{'memory':'128Mi'}},'livenessProbe':{'exec':{'command':['test','-f','/tmp/healthy']},'periodSeconds':1,'failureThreshold':2},'readinessProbe':{'httpGet':{'path':'/','port':8080},'periodSeconds':1}}]}}}})
rollout();original=get('deployment','app')['spec']
s={'apiVersion':'shadok.org/v1alpha1','kind':'DevelopmentSession','metadata':{'name':'live','namespace':NS},'spec':{'enabled':True,'deployment':'app','container':'app','runAsUser':1000,'runAsGroup':1000,'directories':[{'name':'app','imagePath':'/app','mountPath':'/app'}],'start':{'command':command},'podTemplatePatch':{'spec':{'containers':[{'name':'app','livenessProbe':None,'resources':{'requests':{'cpu':'100m'}}}]}}}}
def changed():
    generation=str(get('developmentsession','live')['metadata']['generation'])
    return get('deployment','app')['spec']['template']['metadata'].get('annotations',{}).get('shadok.org/live-generation')==generation
try:
    apply(s)
    stored=json.loads(get('developmentsession','live')['spec']['podTemplatePatch'])['spec']['containers'][0]
    assert 'livenessProbe' in stored and stored['livenessProbe'] is None,'CRD pruned null removal'
    wait(changed);rollout()
    app=get('deployment','app')['spec']['template']['spec']['containers'][0]
    assert 'livenessProbe' not in app and app['resources']['requests']['cpu']=='100m'
    assert app['readinessProbe']==original['template']['spec']['containers'][0]['readinessProbe']
    assert app['resources']['limits']['memory']=='128Mi'
    before=pod();kub('-n',NS,'exec',before['metadata']['name'],'-c','app','--','rm','/tmp/healthy')
    time.sleep(6)
    after=pod()
    assert before['metadata']['uid']==after['metadata']['uid']
    status=lambda p:next(c for c in p['status']['containerStatuses'] if c['name']=='app')
    assert status(before)['containerID']==status(after)['containerID'] and status(after)['restartCount']==0
    print('PASS: CRD retained null; liveness disabled; failing health check did not restart container; CPU changed, memory/readiness preserved',flush=True)
    kub('-n',NS,'exec',before['metadata']['name'],'-c','app','--','touch','/tmp/healthy')
    s['spec']['podTemplatePatch']['spec']['containers'][0]={'name':'app','resources':{'requests':{'cpu':'200m'}}}
    apply(s);wait(changed);rollout()
    app=get('deployment','app')['spec']['template']['spec']['containers'][0]
    assert app['livenessProbe']==original['template']['spec']['containers'][0]['livenessProbe'] and app['resources']['requests']['cpu']=='200m'
    del s['spec']['podTemplatePatch'];apply(s);wait(changed);rollout()
    assert get('deployment','app')['spec']['template']['spec']['containers'][0]['resources']==original['template']['spec']['containers'][0]['resources']
    print('PASS: editing patch restored omitted liveness; removing patch restored original resources',flush=True)
finally:
    s['spec']['enabled']=False;apply(s)
    wait(lambda:get('deployment','app')['spec']==original);rollout()
print('PASS: exact baseline restored after disabling session',flush=True)
