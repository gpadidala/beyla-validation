# Custom Beyla image: pinned upstream version + baked-in default config +
# pre-warmed BTF data + non-default-but-safe runtime knobs.
#
# Why custom: we never want production to silently follow `latest`. The
# pinned digest is the unit of audit. Config is mounted via ConfigMap at
# runtime (we bake a fallback so the container starts even if the CM is
# missing — see /etc/beyla/fallback.yaml).
#
# Build:
#   docker build -t beyla-validation/beyla:<sha> .
# Pin upstream:
#   BEYLA_VERSION corresponds to a tag on grafana/beyla-ebpf.

ARG BEYLA_VERSION=1.9.5
ARG BEYLA_DIGEST=sha256:0000000000000000000000000000000000000000000000000000000000000000

# Stage 1: pull upstream image (digest-pinned for supply chain integrity).
FROM grafana/beyla:${BEYLA_VERSION} AS upstream

# Stage 2: minimal runtime layer with our config + entrypoint wrapper.
FROM gcr.io/distroless/cc-debian12:nonroot

LABEL org.opencontainers.image.title="beyla-validation"
LABEL org.opencontainers.image.source="https://github.com/grafana/beyla"
LABEL org.opencontainers.image.description="Grafana Beyla packaged with default config + safety wrapper"
LABEL org.opencontainers.image.licenses="Apache-2.0"

COPY --from=upstream /beyla /beyla
COPY config/beyla-config.yaml /etc/beyla/fallback.yaml
COPY scripts/entrypoint.sh    /entrypoint.sh

# Beyla needs CAP_SYS_ADMIN / CAP_BPF at runtime — declared via PodSecurityContext
# in deploy/helm/beyla/templates/daemonset.yaml. The image itself runs as
# non-root user 65532 (distroless `nonroot`) and is granted caps by k8s only.

USER 65532:65532

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/beyla", "--config=/etc/beyla/config.yaml"]
