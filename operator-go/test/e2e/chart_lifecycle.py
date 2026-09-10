#!/usr/bin/env python3
"""Install/upgrade/rollback/uninstall integration in the dedicated Kind cluster. Run from repository root."""
import os,subprocess,json,time
NS='shadok-chart-review'
K=['kubectl','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--context','kind-shadok-go-e2e']
H=['helm','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--kube-context','kind-shadok-go-e2e']
E=dict(os.environ,HELM_CACHE_HOME='/tmp/shadok-helm-cache',HELM_CONFIG_HOME='/tmp/shadok-helm-config',HELM_DATA_HOME='/tmp/shadok-helm-data')
def run(a,check=True):return subprocess.run(a,env=E,text=True,capture_output=True,check=check)
v={'operator':{'image':{'tag':'local'},'toolImage':{'tag':'local'},'watchNamespaces':[NS]},'gateway':{'image':{'tag':'local'}},'session':{'create':True,'name':'guard-check','deployment':'missing-fixture','directories':[{'name':'app','imagePath':'/app','mountPath':'/app'}],'start':{'command':['run']}}}
open('/tmp/shadok-chart-lifecycle-values.json','w').write(json.dumps(v))
base=H+['upgrade','--install','chart-review','operator-go/chart','-n',NS,'--create-namespace','-f','/tmp/shadok-chart-lifecycle-values.json','--wait','--timeout','120s']
existing=run(K+['get','namespace',NS],False)
if existing.returncode==0:
 releases=json.loads(run(H+['list','-n',NS,'-o','json']).stdout)
 assert not releases, 'review namespace already contains a release'
print(run(base).stdout,flush=True)
print(run(H+['test','chart-review','-n',NS,'--timeout','90s','--logs']).stdout,flush=True)
# Exercise HA upgrade and rollback on the dedicated empty application scope.
print(run(base+['--set','operator.replicas=2','--set','operator.pdb.enabled=true','--set','metrics.enabled=true']).stdout,flush=True)
print(run(H+['rollback','chart-review','1','-n',NS,'--wait','--timeout','120s']).stdout,flush=True)
run(K+['-n',NS,'patch','developmentsession','guard-check','--type','merge','-p','{"spec":{"enabled":true}}'])
r=run(H+['uninstall','chart-review','-n',NS,'--timeout','90s'],False)
assert r.returncode!=0,'unsafe uninstall succeeded'
assert run(K+['-n',NS,'get','deployment','chart-review-shadok']).returncode==0
print('PASS: active session blocks uninstall and controller remains',flush=True)
run(K+['-n',NS,'patch','developmentsession','guard-check','--type','merge','-p','{"spec":{"enabled":false}}'])
for _ in range(60):
 s=json.loads(run(K+['-n',NS,'get','developmentsession','guard-check','-o','json']).stdout)
 if not s['metadata'].get('finalizers'):break
 time.sleep(1)
else:raise AssertionError('finalizer not cleared')
print(run(H+['uninstall','chart-review','-n',NS,'--timeout','90s']).stdout,flush=True)
print('PASS: install, Helm test, HA upgrade, rollback, active guard rejection, restored uninstall',flush=True)
