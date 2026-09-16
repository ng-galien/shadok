# Operate Shadok permissions

Use a platform administrator identity for the installation and for configuring sessions. Grant a developer access only to the named session they will activate. Replace the example context, namespace, Deployment, session and identity with the values for your environment.

## 1. Install and verify the admission boundary

Install the operator chart on Kubernetes 1.30 or newer with `operator.enabled: true` and `sessionAdmission.enabled: true` (both are defaults). The chart installs a cluster-scoped `ValidatingAdmissionPolicy` and `ValidatingAdmissionPolicyBinding`. Application-only releases with `operator.enabled: false` do **not** install them: the shared operator installation must provide this protection before granting session write access.

```sh
kubectl --context company-dev version
helm --kube-context company-dev -n shadok-system get values shadok -a
kubectl --context company-dev get validatingadmissionpolicies,validatingadmissionpolicybindings
kubectl --context company-dev get validatingadmissionpolicy shadok-shadok-system-sessions -o yaml
kubectl --context company-dev get validatingadmissionpolicybinding shadok-shadok-system-sessions -o yaml
```

Adjust the policy name if the chart name or release namespace differs: it follows `<chart-name>-<operator-namespace>-sessions`. Check that the policy has `failurePolicy: Fail`, no `status.typeChecking.expressionWarnings`, and its binding has `validationActions: [Deny]` and names that policy. Inspect the rendered chart when using overrides. Do not delegate session writes if either object is absent, invalid or bound with a non-denying action. A chart upgrade with `sessionAdmission.enabled: false` removes these objects; reserve that setting for an already enforced equivalent admission policy.

## 2. Give the platform ownership of session configuration

The platform release or deployment CI creates and configures the `DevelopmentSession` in the application namespace. Its Kubernetes identity needs permission to manage that session **and** to `patch` the named target Deployment; it also needs its normal Helm/chart installation rights. Review the configuration before giving a developer access: `start`, `init`, `directories`, `volumes`, `image` and `podTemplatePatch` can alter code execution or add mounts, including Secrets. Existing sessions are not retroactively checked when the admission policy is installed.

```sh
kubectl --context company-dev -n team-a get developmentsession orders-live -o yaml
kubectl --context company-dev -n team-a auth can-i patch deployments.apps \
  --resource-name=orders --as=system:serviceaccount:team-a:platform-ci
kubectl --context company-dev -n team-a auth can-i patch developmentsessions.shadok.org \
  --resource-name=orders-live --as=system:serviceaccount:team-a:platform-ci
```

Check your actual CI identity and target name. The admission rule asks the Kubernetes authorizer whether the **caller** can patch `deployments.apps/<spec.deployment>` in the session's namespace. That right is the gate for creation, deletion and any configuration change. It is not an independent Shadok role. The platform account's other permissions still need normal least-privilege review.

## 3. Bind a developer to one existing session

Create a namespace Role and RoleBinding with the platform identity. For one target, use `resourceNames` and grant `get` and `patch` only; leave out `create`, `delete`, `list`, `watch`, Deployment patching and access to admission policies. Bind the real SSO user or group instead of the example subject:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: team-a
  name: shadok-orders-live
rules:
  - apiGroups: [shadok.org]
    resources: [developmentsessions]
    resourceNames: [orders-live]
    verbs: [get, patch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  namespace: team-a
  name: shadok-orders-live-developers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: shadok-orders-live
subjects:
  - kind: Group
    name: team-a-developers
    apiGroup: rbac.authorization.k8s.io
```

Kubernetes RBAC controls which **resource names** can be patched; it cannot distinguish `spec.enabled` from `spec.volumes` or `spec.podTemplatePatch`. Admission compares the old and new session, including the configuration fields and protected metadata. Without Deployment patch permission, it accepts only a change to `spec.enabled`; creating, deleting or reconfiguring a session is denied. If one identity also holds Deployment patch permission through another Role, ClusterRole or group, it is a platform configurator for that target, regardless of the Role above. Check the *effective* permissions, not just this binding. A `resourceNames` rule for `list`/`watch` would additionally require a matching `metadata.name` field selector; omit those verbs unless needed.

## 4. Verify with the actual identities

An administrator can impersonate identities for a dry run. Use the same identity form as the RoleBinding subject; for a group, specify a user and `--as-group=team-a-developers`. The examples below assume the session is currently disabled. These checks do not mutate the live session.

```sh
kubectl --context company-dev -n team-a auth can-i patch developmentsessions.shadok.org \
  --resource-name=orders-live --as=developer@example.com --as-group=team-a-developers
kubectl --context company-dev -n team-a auth can-i patch deployments.apps \
  --resource-name=orders --as=developer@example.com --as-group=team-a-developers

kubectl --context company-dev -n team-a --as=developer@example.com \
  --as-group=team-a-developers patch developmentsession orders-live --type=merge \
  --dry-run=server -p '{"spec":{"enabled":true}}'
kubectl --context company-dev -n team-a --as=developer@example.com \
  --as-group=team-a-developers patch developmentsession orders-live --type=merge \
  --dry-run=server -p '{"spec":{"podTemplatePatch":"spec: {serviceAccountName: other}"}}'
```

Expect `yes`, then `no`, then an accepted dry run, then an admission denial. Repeat the denied test with `spec.volumes` or `spec.start` if needed. If the developer can patch the Deployment or the configuration dry run succeeds, inspect their other bindings before using the environment. Repeat the tests after changes to identity groups, RBAC, admission policies or the chart. Use a platform identity for session edits, then have the developer activate it with the same `spec.enabled` patch *without* `--dry-run=server`.

## Boundary and incident checks

The operator's own permissions are set by the chart: with `operator.watchNamespaces` empty, it has cluster-scoped Deployment and ConfigMap permissions; configure watched namespaces to scope the controller and gateway to the intended application namespaces. This scope does not replace the admission rule. The gateway's account reads sessions and pods. The developer does not need permissions to read pods or Secrets to publish a build.

The sync gateway currently has **no built-in writer authentication**. Kubernetes RBAC and the session admission policy do not authorize HTTP uploads: protect gateway access with your ingress/proxy or trusted network. Anyone able to publish into a live session can run code with the application's existing credentials. Choose appropriate development workloads and data. For access failures, distinguish RBAC `Forbidden` (resource access), admission denial (configuration change), and gateway/proxy rejection (HTTP publication). See `shadok learn network` for the latter.

Kubernetes references: [RBAC resource names](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#referring-to-resources), [ValidatingAdmissionPolicy](https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy/).
