# Build-side wrapper for the Airflow image. Deployment stays in
# docker-compose.yaml: set AIRFLOW_IMAGE_NAME to the reference printed here.
#
#   make image                         print the image reference
#   make build                         build and tag the image locally
#   make save                          build, then write dist/<image>.tar.gz + .sha256 for file transfer
#   make push REGISTRY=reg.example.sa  build, then push (only when a registry exists)
#
# The tag is <airflow version from the Dockerfile>-<rev>.
#   In a git repo:  rev = short commit sha, plus -dirty when anything is
#                   uncommitted. save and push refuse a -dirty rev.
#   Without git:    rev = UTC timestamp, so every run gets a new tag.
#   Either way:     REV=<name> overrides it.

.NOTPARALLEL:

REGISTRY   ?=
IMAGE_NAME ?= ihc/airflow

ifndef AIRFLOW_VERSION
AIRFLOW_VERSION := $(shell sed -nE 's|^FROM +apache/airflow:([^@[:space:]]+).*|\1|p' Dockerfile | head -n1)
endif
ifeq ($(strip $(AIRFLOW_VERSION)),)
$(error Could not read the Airflow version from the Dockerfile FROM line; pass AIRFLOW_VERSION=<version>)
endif

ifndef REV
GIT_SHA := $(shell git rev-parse --short HEAD 2>/dev/null)
ifneq ($(GIT_SHA),)
REV := $(GIT_SHA)$(if $(shell git status --porcelain 2>/dev/null),-dirty)
else
REV := $(shell date -u +%Y%m%d%H%M)
endif
endif

IMAGE   := $(if $(REGISTRY),$(REGISTRY:/=)/)$(IMAGE_NAME):$(AIRFLOW_VERSION)-$(REV)
ARCHIVE := dist/$(subst /,_,$(subst :,_,$(IMAGE))).tar

.PHONY: image build save push check-clean check-registry

image:
	@echo $(IMAGE)

build:
	docker build \
	  --label org.opencontainers.image.version=$(AIRFLOW_VERSION) \
	  --label org.opencontainers.image.revision=$(REV) \
	  -t $(IMAGE) .
	@echo "Built $(IMAGE)"

check-clean:
	@case "$(REV)" in *-dirty) \
	  echo "Uncommitted changes: commit first, or pass REV=<name>." >&2; exit 1;; \
	esac

check-registry:
	@test -n "$(REGISTRY)" || { echo "No registry set: pass REGISTRY=<host[/path]>, or use 'make save'." >&2; exit 1; }

save: check-clean build
	mkdir -p dist
	docker save -o $(ARCHIVE) $(IMAGE)
	gzip -f $(ARCHIVE)
	cd dist && sha256sum $(notdir $(ARCHIVE)).gz > $(notdir $(ARCHIVE)).gz.sha256
	@echo "Wrote $(ARCHIVE).gz (load with: docker load -i $(notdir $(ARCHIVE)).gz)"

push: check-registry check-clean build
	docker push $(IMAGE)
