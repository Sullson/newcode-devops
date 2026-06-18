#!/bin/sh
# Render /tmp/proof.json from the pod's own Kubernetes Downward API + the image
# and cluster facts Helm passes in. nginx serves it at /proof.json (see
# nginx.conf) so the page can show — live — which AKS pod/node is answering.
#
# WHY this is honest proof: these values are produced inside the pod by the
# kubelet (NODE_NAME is the real aks-*-vmss node), not asserted by the page. The
# always-on Static Web Apps front has no pod, so /proof.json simply does not
# exist there. That asymmetry is the tell.
#
# WHAT it must never contain: only the whitelisted, public fields below. No
# `env` dump — the pod also carries the workload-identity client id, the Key
# Vault tenant id and a CSI-mounted tunnel token, none of which belong here.
#
# Runs under the official nginx-unprivileged entrypoint (/docker-entrypoint.d),
# as the container user, writing to the writable /tmp emptyDir.
set -e

cat > /tmp/proof.json <<EOF
{
  "servedBy": "aks",
  "pod": "${POD_NAME:-unknown}",
  "node": "${NODE_NAME:-unknown}",
  "namespace": "${POD_NAMESPACE:-unknown}",
  "cluster": "${CLUSTER_NAME:-}",
  "region": "${CLUSTER_REGION:-}",
  "apiDomain": "${CLUSTER_API_DOMAIN:-}",
  "image": "${IMAGE_REF:-unknown}",
  "digest": "${IMAGE_DIGEST:-}",
  "renderedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
