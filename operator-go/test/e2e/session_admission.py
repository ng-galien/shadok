#!/usr/bin/env python3
"""Verify session authorization using an impersonated developer on dedicated Kind."""
import json, os, pathlib, subprocess, tempfile, time
K = ['kubectl', '--kubeconfig', '/tmp/shadok-go-e2e.kubeconfig', '--context', 'kind-shadok-go-e2e']
NS = 'shadok-admission-e2e'
USER = 'shadok-admission-developer'
def run(args, data=None, ok=True):
    p = subprocess.run(K + args, input=json.dumps(data) if data is not None else None, text=True, capture_output=True)
    assert (p.returncode == 0) == ok, p.stdout + p.stderr
    return p.stdout if ok else p.stderr

def apply(obj): return run(['apply','-f','-'], obj)
with tempfile.TemporaryDirectory() as td:
    env=dict(os.environ, HELM_CACHE_HOME=td, HELM_CONFIG_HOME=td, HELM_DATA_HOME=td)
    chart=pathlib.Path(__file__).resolve().parents[2]/'chart'
    policy=subprocess.check_output(['helm','template','admission-test',str(chart),'--namespace',NS,'--kube-version','1.30.0','--show-only','templates/session-admission.yaml'],env=env,text=True)
    path=pathlib.Path(td)/'policy.yaml'; path.write_text(policy)
    apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':NS}})
    run(['apply','-f',str(path)])
    try:
        apply({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'Role','metadata':{'name':'developer','namespace':NS},'rules':[{'apiGroups':['shadok.org'],'resources':['developmentsessions'],'verbs':['get','create','patch','update','delete']}]})
        apply({'apiVersion':'rbac.authorization.k8s.io/v1','kind':'RoleBinding','metadata':{'name':'developer','namespace':NS},'roleRef':{'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':'developer'},'subjects':[{'kind':'User','name':USER}]})
        name='admission-test-shadok-'+NS+'-sessions'
        for _ in range(60):
            status=json.loads(run(['get','validatingadmissionpolicy',name,'-o','json'])).get('status',{})
            if status.get('observedGeneration'):
                assert not status.get('typeChecking',{}).get('expressionWarnings'), status
                break
            time.sleep(.5)
        else: raise AssertionError('admission policy not checked')
        session={'apiVersion':'shadok.org/v1alpha1','kind':'DevelopmentSession','metadata':{'name':'live','namespace':NS},'spec':{'enabled':False,'deployment':'app','container':'app','runAsUser':1000,'runAsGroup':1000,'directories':[{'name':'app','mountPath':'/app'}],'start':{'command':['java']}}}
        apply(session)
        dev=['--as',USER,'-n',NS]
        patches=[('activation',{'enabled':True},True),('command',{'start':{'command':['other']}},False),('pod patch',{'podTemplatePatch':'spec: {serviceAccountName: other}'},False),('Secret',{'volumes':[{'name':'secret','mountPath':'/secret','secret':{'secretName':'other'}}]},False),('image',{'image':'other'},False)]
        for label,patch,allowed in patches:
            result=run(dev+['patch','developmentsession','live','--type=merge','--dry-run=server','-p',json.dumps({'spec':patch})],ok=allowed)
            if not allowed: assert 'Only enabled' in result,result
            print(label, 'allowed' if allowed else 'denied')
        run(dev+['delete','developmentsession','live','--dry-run=server'],ok=False)
        session['metadata']['name']='new'
        run(dev+['create','--dry-run=server','-f','-'],session,ok=False)
        run(['-n',NS,'patch','developmentsession','live','--type=merge','--dry-run=server','-p',json.dumps({'spec':{'start':{'command':['platform-update']}}})])
        print('PASS: developer limited to activation; platform configuration allowed; CEL has no warnings')
    finally:
        run(['delete','-f',str(path),'--ignore-not-found'])
        run(['delete','namespace',NS,'--wait=false'])
