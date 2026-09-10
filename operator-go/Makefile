GO ?= go
ARCH ?= $(shell $(GO) env GOARCH)
VERSION ?= $(shell cat ../VERSION)
IMAGE_PREFIX ?=
BUILD_IMAGE ?= golang:1.26
RUNTIME_IMAGE ?= gcr.io/distroless/static:nonroot
CONTROLLER_GEN_VERSION := v0.20.1
LDFLAGS := -s -w -X shadok.org/operator/internal/buildinfo.Version=$(VERSION) -X shadok.org/operator/internal/buildinfo.ImagePrefix=$(IMAGE_PREFIX)
.PHONY: generate test build generic verify image generic-images linux local-e2e chart-test chart-package release release-test

generate:
	$(GO) run sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_GEN_VERSION) object crd paths=./api/... output:crd:artifacts:config=chart/crds

test:
	$(GO) test -race ./...

build generic:
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags='$(LDFLAGS)' -o bin/shadok ./cmd/shadok
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags='$(LDFLAGS)' -o bin/operator ./cmd/operator
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags='$(LDFLAGS)' -o bin/gateway ./cmd/gateway

release-test:
	python3 -m unittest discover -s test/release -v

verify: test build release-test
	$(GO) vet ./...

linux:
	CGO_ENABLED=0 GOOS=linux GOARCH=$(ARCH) $(GO) build -trimpath -ldflags='$(LDFLAGS)' -o bin/linux/shadok ./cmd/shadok
	CGO_ENABLED=0 GOOS=linux GOARCH=$(ARCH) $(GO) build -trimpath -ldflags='$(LDFLAGS)' -o bin/linux/operator ./cmd/operator
	CGO_ENABLED=0 GOOS=linux GOARCH=$(ARCH) $(GO) build -trimpath -ldflags='$(LDFLAGS)' -o bin/linux/gateway ./cmd/gateway

image generic-images:
	docker build --platform linux/$(ARCH) --target tools --build-arg VERSION=$(VERSION) --build-arg IMAGE_PREFIX=$(IMAGE_PREFIX) --build-arg BUILD_IMAGE=$(BUILD_IMAGE) --build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) -t shadok-tools:local .
	docker build --platform linux/$(ARCH) --target operator --build-arg VERSION=$(VERSION) --build-arg IMAGE_PREFIX=$(IMAGE_PREFIX) --build-arg BUILD_IMAGE=$(BUILD_IMAGE) --build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) -t shadok-operator:local .
	docker build --platform linux/$(ARCH) --target gateway --build-arg VERSION=$(VERSION) --build-arg IMAGE_PREFIX=$(IMAGE_PREFIX) --build-arg BUILD_IMAGE=$(BUILD_IMAGE) --build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) -t shadok-gateway:local .

local-e2e: build
	python3 test/e2e/local_daemon.py

chart-test:
	$(GO) test ./test/chart

chart-package:
	helm lint chart --strict
	helm package chart --destination dist

release:
	python3 scripts/package.py --version $(VERSION) --image-prefix $(IMAGE_PREFIX)
