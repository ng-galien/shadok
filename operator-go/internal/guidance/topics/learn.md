# Operate Shadok with this binary

Shadok temporarily transforms an existing Kubernetes Deployment for live development and restores its saved PodTemplate when disabled. The operator is runtime-agnostic: the application image provides the tools and dependencies; a DevelopmentSession declares directories and its live command. The CLI starts a local daemon and sends file revisions over HTTP(S) to the gateway. It does not use Kubernetes credentials for synchronization. There is no editor extension to install.

Start with `shadok --help` and `shadok version`. All instructions below are embedded in this binary and work offline:

- `shadok docs install`: inspect the target cluster, export the bundled chart, configure images/networking, install and verify.
- `shadok docs configure`: create a session, project groups and a personal destination; enable and verify live mode.
- `shadok docs builds`: working Node, TypeScript, Python, Maven and Gradle integration examples.
- `shadok docs lifecycle`: upgrades, restoration, uninstall, troubleshooting and current limits.
- `shadok docs chart`: full chart reference; `shadok docs values`, `shadok docs schema` and `shadok docs crd` expose the actual bundled assets.
- `shadok docs all`: all operational topics and the chart reference in one output.
- `shadok chart export ./shadok-chart`: materialize every chart template, schema and CRD without a checkout.
- `shadok agent install --client codex`: install a minimal skill that directs the agent to `shadok learn`. Operational documentation stays in the binary. Claude is supported with `--client claude`; `--path DIRECTORY` selects an exact skill directory for other clients.
- `shadok agent status --client codex`: verify managed files against their recorded hashes and this binary. `agent uninstall` removes only an unchanged managed installation.

For an agent: inspect the actual application Deployment, build outputs, requested cluster context and existing releases before choosing configuration. Continue authorized setup through a real application change, revision ACK, application response and restoration check. Use existing session authorization; ask only for genuinely missing target/credentials or additional external publication. A successful Helm test proves gateway TCP reachability, not application reload. Keep project-specific instructions outside the installed skill directory.

Reading help/docs never starts a daemon, touches a cluster or downloads anything. Installation needs kubectl/Helm and cluster permissions; workloads need accessible container images. This binary supplies the chart and instructions, not container image layers or cluster credentials. Do not invent a published registry URL: use the supplied release's image references or ask the platform owner for them.
