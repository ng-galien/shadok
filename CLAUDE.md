# Shadok development guidance

The active implementation is the Go module in `operator-go/`. Spring and Quarkus are application demos; operator behavior must remain independent of application languages.

Read `operator-go/README.md`, `operator-go/chart/README.md` and `docs/OPERATOR_REVIEW.md` before changing contracts. A DevelopmentSession transforms an existing Deployment in place and restores its exact baseline PodTemplate. Do not introduce a runtime/language enum or separate application Deployment. Application images and start commands select runtime behavior.

Run `make -C operator-go generate verify`, `make -C operator-go chart-test`, and relevant end-to-end tests. CRD and deepcopy output are generated with the pinned controller-gen version in the Makefile. Helm unit tests execute actual rendering and validate resulting objects and failures.

Only use the dedicated `kind-shadok-go-e2e` context and `/tmp/shadok-go-e2e.kubeconfig` for local integration work. Do not delete clusters or unrelated fixtures. Do not publish artifacts or push commits without authorization. Preserve unrelated working changes.

Never give the CLI or daemon Kubernetes credentials to solve an HTTP sync failure. Gateway permissions are read-only; the operator alone patches Deployments. Build snapshots are published only after a successful local build. Authentication, distributed writer leases and whole-tree atomic updates are not implemented; do not claim otherwise.
