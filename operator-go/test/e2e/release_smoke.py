#!/usr/bin/env python3
"""Consume public release artifacts in a fresh dedicated Kind; never build Shadok."""
import argparse, hashlib, json, os, pathlib, platform, subprocess, tarfile, tempfile
p=argparse.ArgumentParser();p.add_argument('--version',default='1.0.0');a=p.parse_args()
root=pathlib.Path(__file__).resolve().parents[3]
cluster='shadok-release-smoke'
def run(cmd,**kw):return subprocess.run(cmd,check=True,**kw)
clusters=subprocess.check_output(['kind','get','clusters'],text=True).splitlines()
if cluster in clusters:raise SystemExit('Refusing reused cluster shadok-release-smoke; inspect and remove it explicitly before rerunning.')
work=pathlib.Path(tempfile.mkdtemp(prefix='shadok-release-consumer-'))
system={'Darwin':'darwin','Linux':'linux'}[platform.system()]
arch={'arm64':'arm64','aarch64':'arm64','x86_64':'amd64'}[platform.machine()]
archive=f'shadok_{a.version}_{system}_{arch}.tar.gz'
base=f'https://github.com/ng-galien/shadok/releases/download/v{a.version}/'
for name in (archive,f'SHA256SUMS-{a.version}'):
    run(['curl','--fail','--location','--proto','=https','--tlsv1.2','--output',str(work/name),base+name])
checks={line.split()[1]:line.split()[0] for line in (work/f'SHA256SUMS-{a.version}').read_text().splitlines()}
assert hashlib.sha256((work/archive).read_bytes()).hexdigest()==checks[archive]
with tarfile.open(work/archive) as bundle:bundle.extractall(work/'cli',filter='data')
binary=work/'cli/shadok'
assert subprocess.check_output([str(binary),'--version'],text=True).strip()==a.version
# Empty Helm credentials demonstrate public OCI consumption.
env=dict(os.environ,HELM_REGISTRY_CONFIG=str(work/'registry.json'))
chart='oci://ghcr.io/ng-galien/shadok/charts/shadok'
run(['helm','pull',chart,'--version',a.version,'--destination',str(work)],env=env)
chart_file=work/f'shadok-{a.version}.tgz'
assert hashlib.sha256(chart_file.read_bytes()).hexdigest()==checks[chart_file.name]
config=work/'kind.yaml'
config.write_text('''kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 30443
    hostPort: 18443
    listenAddress: "127.0.0.1"
  - containerPort: 30081
    hostPort: 18081
    listenAddress: "127.0.0.1"
''')
run(['kind','create','cluster','--name',cluster,'--config',str(config),'--kubeconfig',f'/tmp/{cluster}.kubeconfig','--wait','120s'])
# Only the application fixture is built locally; Shadok images come from GHCR.
run(['docker','build','-t','shadok-baseline:local','-f',str(root/'operator-go/test/e2e/Dockerfile.baseline'),str(root/'operator-go/test/e2e')])
run(['kind','load','docker-image','--name',cluster,'shadok-baseline:local'])
env.update(SHADOK_TEST_CLUSTER=cluster,SHADOK_TEST_BINARY=str(binary),SHADOK_TEST_CHART=chart,SHADOK_TEST_VERSION=a.version)
run(['python3',str(root/'operator-go/test/e2e/kind_e2e.py'),'--stack','baseline'],env=env)
k=['kubectl','--kubeconfig',f'/tmp/{cluster}.kubeconfig','--context','kind-'+cluster]
run(['helm','--kubeconfig',f'/tmp/{cluster}.kubeconfig','--kube-context','kind-'+cluster,'test','runtime','-n','shadok-live-system','--logs'],env=env)
pods=json.loads(subprocess.check_output(k+['get','pods','-A','-o','json'],text=True))
images=[{'pod':p['metadata']['name'],'image':c['image'],'imageID':c.get('imageID')} for p in pods['items'] for c in p.get('status',{}).get('containerStatuses',[]) if c['image'].startswith('ghcr.io/ng-galien/shadok/')]
assert any('/operator:' in c['image'] for c in images) and any('/gateway:' in c['image'] for c in images)
evidence={'version':a.version,'chart':chart,'cliSHA256':checks[archive],'images':images,'checks':['anonymous CLI and chart download','checksum verification','fresh Kind registry installation','HTTPS direct NodePort','CR-only identity','two-replica sync','failed build preserves last revision','successful build publication','add/delete','pod replacement','exact restoration','helm test']}
(work/'evidence.json').write_text(json.dumps(evidence,indent=2)+'\n')
print('PASS release consumer; evidence:',work/'evidence.json',flush=True)
print('Cluster retained for inspection:',cluster,flush=True)
