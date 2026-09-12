#!/usr/bin/env python3
"""Destructive CRD lifecycle test, only for the dedicated shadok-go-e2e cluster.
Requires the operator under test deployed as runtime-shadok. Saves inactive fixtures.
"""
import copy,json,subprocess,time,tempfile
K=['kubectl','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--context','kind-shadok-go-e2e']
NS='shadok-live-e2e'; SYSTEM='shadok-live-system'; NAME='finalizer-lifecycle'
def k(*args):return subprocess.check_output(K+list(args),text=True,stderr=subprocess.STDOUT)
def get(kind,name,ns=NS):return json.loads(k('-n',ns,'get',kind,name,'-o','json'))
def apply(v):subprocess.run(K+['apply','-f','-'],input=json.dumps(v),text=True,check=True,stdout=subprocess.DEVNULL)
def wait(fn):
    for _ in range(90):
        if fn():return
        time.sleep(1)
    raise AssertionError('condition timed out')
def scale(n):
    k('-n',SYSTEM,'scale','deployment/runtime-shadok','--replicas='+str(n))
    if n:k('-n',SYSTEM,'rollout','status','deployment/runtime-shadok','--timeout=120s')
    else:wait(lambda:not json.loads(k('-n',SYSTEM,'get','pods','-l','app.kubernetes.io/component=operator','-o','json'))['items'])
def absent():return not k('-n',NS,'get','developmentsession',NAME,'--ignore-not-found').strip()
def template():return get('deployment',NAME)['spec']['template']
def delete_session():
    start=time.monotonic();k('-n',NS,'delete','developmentsession',NAME,'--wait=true','--timeout=10s')
    assert absent();print('PASS deletion completes in %.2fs'%(time.monotonic()-start),flush=True)
fixtures=json.loads(k('get','developmentsessions','-A','-o','json'))['items']
assert all(not s['spec']['enabled'] and not s['metadata'].get('finalizers') for s in fixtures),'requires inactive fixtures'
for s in fixtures:
    s.pop('status',None)
    for key in ['uid','resourceVersion','generation','creationTimestamp','managedFields']:s['metadata'].pop(key,None)
crd=json.loads(k('get','crd','developmentsessions.shadok.org','-o','json'))
crd.pop('status',None)
for key in ['uid','resourceVersion','generation','creationTimestamp','managedFields']:crd['metadata'].pop(key,None)
original=get('deployment','spring');d={'apiVersion':'apps/v1','kind':'Deployment','metadata':{'name':NAME,'namespace':NS},'spec':original['spec']}
d['spec']['replicas']=0;d['spec']['selector']={'matchLabels':{'app':NAME}};d['spec']['template']['metadata']['labels']={'app':NAME}
s=get('developmentsession','spring');s={'apiVersion':s['apiVersion'],'kind':s['kind'],'metadata':{'name':NAME,'namespace':NS},'spec':s['spec']};s['spec'].update(enabled=True,deployment=NAME)
def activate():
    apply(d);base=copy.deepcopy(template());apply(s)
    wait(lambda:template()['metadata'].get('annotations',{}).get('shadok.org/live-session'))
    assert not get('developmentsession',NAME)['metadata'].get('finalizers')
    return base
try:
    for case in ['normal','drift','replaced','missing','stopped','legacy']:
        base=activate()
        if case=='drift':
            k('-n',NS,'patch','deployment',NAME,'--type=merge','-p',json.dumps({'spec':{'template':{'metadata':{'annotations':{'external':'keep'}}}}}))
            base['metadata'].setdefault('annotations',{})['external']='keep'
        if case in ('missing','replaced'):
            k('-n',NS,'delete','deployment',NAME,'--wait=true')
            if case=='replaced':apply(d);base=template()
        if case=='legacy':
            scale(0)
            legacy=get('developmentsession',NAME)
            uid=legacy['metadata']['uid']
            cm=get('configmap',uid+'-baseline')
            cm['metadata'].pop('labels',None)
            cm['metadata']['ownerReferences']=[{'apiVersion':s['apiVersion'],'kind':s['kind'],'name':NAME,'uid':uid,'controller':True}]
            cm['data'].pop('session',None)
            subprocess.run(K+['replace','-f','-'],input=json.dumps(cm),text=True,check=True,stdout=subprocess.DEVNULL)
            k('-n',NS,'patch','developmentsession',NAME,'--type=merge','-p',json.dumps({'metadata':{'finalizers':['shadok.org/restore-baseline']}}))
            k('-n',NS,'delete','developmentsession',NAME,'--wait=false')
            assert get('developmentsession',NAME)['metadata']['finalizers']
            scale(1);wait(absent)
        else:
            if case=='stopped':scale(0)
            delete_session()
        if case=='stopped':
            assert template()['metadata']['annotations'].get('shadok.org/live-session'),'cleanup unexpectedly ran with operator stopped'
            scale(1)
        if case!='missing':wait(lambda:template()==base)
        wait(lambda:not json.loads(k('-n',NS,'get','configmaps','-l','shadok.org/recovery-session','-o','json'))['items'])
        k('-n',NS,'delete','deployment',NAME,'--ignore-not-found','--wait=true')
        print('PASS '+case+': cleanup completed; external state preserved',flush=True)
    base=activate();scale(0)
    start=time.monotonic();k('delete','crd','developmentsessions.shadok.org','--wait=true','--timeout=15s')
    print('PASS CRD deletion with active session and stopped operator in %.2fs'%(time.monotonic()-start),flush=True)
    # Restart while the CRD is still absent: recovery must use core resources.
    k('-n',SYSTEM,'scale','deployment/runtime-shadok','--replicas=1')
    wait(lambda:template()==base)
    print('PASS baseline restored after operator restart with CRD absent',flush=True)
finally:
    apply(crd);k('wait','--for=condition=Established','crd/developmentsessions.shadok.org','--timeout=60s')
    apply({'apiVersion':'v1','kind':'List','items':fixtures})
    scale(1)
    k('-n',NS,'delete','developmentsession',NAME,'--ignore-not-found','--wait=true','--timeout=10s')
    k('-n',NS,'delete','deployment',NAME,'--ignore-not-found','--wait=true')
