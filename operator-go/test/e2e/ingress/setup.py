#!/usr/bin/env python3
"""Install isolated Ingress fixtures without changing existing Shadok workloads."""
import json,os,pathlib,socket,subprocess
HERE=pathlib.Path(__file__).resolve().parent;ROOT=HERE.parents[3]
NS='shadok-ingress-e2e';SYSTEM='shadok-ingress-system';STATE=pathlib.Path('/tmp/shadok-ingress-local')
SYNC='sync.127.0.0.1.nip.io';APP='app.127.0.0.1.nip.io';BRIDGE='shadok-ingress-local'
K=['kubectl','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--context','kind-shadok-go-e2e']
H=['helm','--kubeconfig','/tmp/shadok-go-e2e.kubeconfig','--kube-context','kind-shadok-go-e2e']
ENV=dict(os.environ,HELM_CACHE_HOME='/tmp/shadok-helm-cache',HELM_CONFIG_HOME='/tmp/shadok-helm-config',HELM_DATA_HOME='/tmp/shadok-helm-data')
def kub(*args,input=None):return subprocess.check_output(K+list(args),input=input,text=True,stderr=subprocess.STDOUT)
def apply(obj):return kub('apply','-f','-',input=json.dumps(obj))
def helm(*args):subprocess.run(H+list(args),env=ENV,check=True)
def resource(kind,name,spec=None,api='v1'):
    obj={'apiVersion':api,'kind':kind,'metadata':{'name':name,'namespace':NS}}
    if spec is not None:obj['spec']=spec
    return obj
def ingress(name,host,service,port,path='/',middleware=None):
    obj=resource('Ingress',name,{'ingressClassName':'shadok-local','tls':[{'hosts':[host],'secretName':'local-tls'}],'rules':[{'host':host,'http':{'paths':[{'path':path,'pathType':'Prefix','backend':{'service':{'name':service,'port':{'number':port}}}}]}}]},'networking.k8s.io/v1')
    obj['metadata']['annotations']={'kubernetes.io/ingress.class':'shadok-local','traefik.ingress.kubernetes.io/router.entrypoints':'websecure','traefik.ingress.kubernetes.io/router.tls':'true'}
    if middleware:obj['metadata']['annotations']['traefik.ingress.kubernetes.io/router.middlewares']=NS+'-'+middleware+'@kubernetescrd'
    return obj
def main():
    assert [n['metadata']['name'] for n in json.loads(kub('get','nodes','-o','json'))['items']]==['shadok-go-e2e-control-plane'],'refusing another cluster'
    for host in [SYNC,APP]:assert socket.gethostbyname(host)=='127.0.0.1',f'{host} must resolve to loopback'
    # Do not mutate an active run's baseline.
    old=subprocess.run(K+['-n',NS,'get','developmentsession','ingress-live','-o','json'],capture_output=True,text=True)
    if old.returncode==0:assert not json.loads(old.stdout)['spec']['enabled'],'disable ingress-live before setup'
    for ns in [NS,SYSTEM]:apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':ns}})
    STATE.mkdir(mode=0o700,exist_ok=True)
    helm('repo','add','traefik','https://traefik.github.io/charts')
    helm('upgrade','--install','shadok-ingress','traefik/traefik','--version','41.5.0','-n',SYSTEM,'-f',str(HERE/'traefik-values.yaml'),'--wait','--timeout','180s')
    subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(STATE/'tls.key'),'-out',str(STATE/'ca.crt'),'-days','2','-subj','/CN='+SYNC,'-addext',f'subjectAltName=DNS:{SYNC},DNS:{APP}','-addext','basicConstraints=critical,CA:TRUE'],check=True,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    os.chmod(STATE/'tls.key',0o600)
    apply(json.loads(kub('-n',NS,'create','secret','tls','local-tls','--cert',str(STATE/'ca.crt'),'--key',str(STATE/'tls.key'),'--dry-run=client','-o','json')))
    apply(resource('ServiceAccount','gateway'))
    role=resource('Role','gateway',api='rbac.authorization.k8s.io/v1');role['rules']=[{'apiGroups':[''],'resources':['pods'],'verbs':['get','list']},{'apiGroups':['shadok.org'],'resources':['developmentsessions'],'verbs':['get','list']}];apply(role)
    binding=resource('RoleBinding','gateway',api='rbac.authorization.k8s.io/v1');binding.update(roleRef={'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':'gateway'},subjects=[{'kind':'ServiceAccount','name':'gateway','namespace':NS}]);apply(binding)
    containers=[('baseline','shadok-baseline:local',8080),('gateway','shadok-gateway:local',8080)]
    for name,image,port in containers:
        container={'name':'app' if name=='baseline' else 'gateway','image':image,'imagePullPolicy':'IfNotPresent','resources':{'requests':{'cpu':'10m','memory':'32Mi'},'limits':{'memory':'256Mi'}}}
        if name=='baseline':container['readinessProbe']={'httpGet':{'path':'/','port':8080},'periodSeconds':1,'initialDelaySeconds':3}
        else:container['readinessProbe']={'tcpSocket':{'port':8080}}
        podspec={'containers':[container]}
        if name=='gateway':podspec['serviceAccountName']='gateway'
        apply(resource('Deployment',name,{'replicas':1,'selector':{'matchLabels':{'app':name}},'template':{'metadata':{'labels':{'app':name}},'spec':podspec}},'apps/v1'))
        apply(resource('Service',name,{'selector':{'app':name},'ports':[{'port':port,'targetPort':port}]}))
        kub('-n',NS,'rollout','status','deployment/'+name,'--timeout=120s')
    for name,limit in [('sync-upload',570425344),('small-limit-probe',1024)]:
        apply(resource('Middleware',name,{'buffering':{'maxRequestBodyBytes':limit,'memRequestBodyBytes':1048576}},'traefik.io/v1alpha1'))
    apply(ingress('sync',SYNC,'gateway',8080,middleware='sync-upload'))
    apply(ingress('application',APP,'baseline',8080))
    apply(ingress('limit-probe',SYNC,'gateway',8080,path='/__limit_probe',middleware='small-limit-probe'))
    values={'operator':{'enabled':False},'session':{'create':True,'name':'ingress-live','deployment':'baseline','container':'app','enabled':False,'runAsUser':1000,'runAsGroup':1000,'directories':[{'name':'application','imagePath':'/app','mountPath':'/app'}],'start':{'command':['python'],'args':['-m','http.server','8080','--directory','/app'],'workingDir':'/app'}}}
    vf=STATE/'session-values.json';vf.write_text(json.dumps(values));helm('upgrade','--install','ingress-fixture',str(ROOT/'operator-go/chart'),'-n',NS,'-f',str(vf))
    kub('-n',NS,'apply','-f',str(ROOT/'operator-go/config/developer-role.yaml'));apply(resource('ServiceAccount','developer'))
    binding=resource('RoleBinding','developer',api='rbac.authorization.k8s.io/v1');binding.update(roleRef={'apiGroup':'rbac.authorization.k8s.io','kind':'Role','name':'shadok-developer'},subjects=[{'kind':'ServiceAccount','name':'developer','namespace':NS}]);apply(binding)
    old=subprocess.run(['docker','inspect',BRIDGE],capture_output=True,text=True)
    if old.returncode==0:
        assert json.loads(old.stdout)[0]['Config']['Labels'].get('shadok.local-test')=='ingress','container name belongs to another task'
        subprocess.run(['docker','rm','-f',BRIDGE],check=True,stdout=subprocess.DEVNULL)
    subprocess.run(['docker','run','-d','--name',BRIDGE,'--label','shadok.local-test=ingress','--network','kind','--publish','127.0.0.1:8080:8080','--publish','127.0.0.1:8443:8443','--mount',f'type=bind,source={HERE / "tcp_bridge.py"},target=/tcp_bridge.py,readonly','--entrypoint','python','shadok-baseline:local','/tcp_bridge.py'],check=True)
    ports=json.loads(subprocess.check_output(['docker','inspect',BRIDGE],text=True))[0]['HostConfig']['PortBindings'];assert all(p['HostIp']=='127.0.0.1' for bindings in ports.values() for p in bindings)
    print(f'Ready: https://{SYNC}:8443/{NS}/baseline ; CA {STATE / "ca.crt"}')
if __name__=='__main__':main()
