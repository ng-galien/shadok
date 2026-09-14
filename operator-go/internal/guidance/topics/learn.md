# Shadok operating guides

## 1. Put your application into live mode

Choose **one** guide. Each contains the image inspection, required files, YAML configuration, build/sync commands, verification and return to production. Run it in your application's repository; no Shadok source checkout or sample is required.

| Your application | Complete guide |
| --- | --- |
| Spring Boot JVM, Maven or Gradle | `shadok learn spring` |
| Quarkus JVM, Maven or Gradle | `shadok learn quarkus` |
| Node.js, TypeScript or Vite | `shadok learn node` |
| Python | `shadok learn python` |

Start with the production image and Deployment actually used by your project. Keep the existing chart/Helmfile, routing and configuration. Declare supported tool files or existing tool volumes in the session; the operator prepares their mounts. Other missing runtime dependencies must be supplied by the platform. File synchronization alone does not add reload behavior.

## 2. Administer Shadok — platform team

| Task | Guide |
| --- | --- |
| Install the operator, gateway and permissions | `shadok learn install` |
| Expose the sync gateway through DNS, TLS and Ingress | `shadok learn network` |
| Update the CLI or cluster installation | `shadok learn upgrade` |
| Disable/delete sessions and restore applications | `shadok learn lifecycle` |

Developers can have permissions only on DevelopmentSessions. They declare tool files and mounts in the session; the platform provides any referenced PVCs, Secrets or ConfigMaps. They do not reproduce or replace the platform's deployments. Synchronization clients need gateway access, not Kubernetes credentials.

## 3. Reference — optional

| Subject | Command |
| --- | --- |
| Image/workload inspection checklist | `shadok docs inspect` |
| Session fields and root mapping | `shadok docs configure` |
| Additional build-tool integration patterns | `shadok docs builds` |
| HTTP reload and restoration checks | `shadok docs verify` |
| Exact installed CRD / Helm configuration | `shadok docs crd`, `values`, `schema`, `chart` |
| Export the matching chart | `shadok chart export ./shadok-chart` |

These references supplement the complete runtime guides. They are not prerequisites to assembling a working configuration. All guides are embedded in the CLI and available offline.
