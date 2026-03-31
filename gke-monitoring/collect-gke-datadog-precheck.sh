#!/usr/bin/env bash
set -u

PROJECT_ID="${PROJECT_ID:-gcp-fui-dev}"
CLUSTER_NAME="${CLUSTER_NAME:-gke-fui-dev-cl}"
CLUSTER_LOCATION="${CLUSTER_LOCATION:-southamerica-west1-a}"

OUT="${HOME}/dd-gke-precheck-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"

run() {
  local name="$1"
  shift
  echo "==> ${name}"
  {
    echo "# COMMAND: $*"
    echo
    "$@"
  } > "${OUT}/${name}.txt" 2>&1 || true
}

echo "Output dir: $OUT"

run 01-kubectl-context kubectl config current-context
run 02-cluster-info kubectl cluster-info
run 03-cluster-describe gcloud container clusters describe "$CLUSTER_NAME" --zone "$CLUSTER_LOCATION" --project "$PROJECT_ID"
run 04-nodepools-list gcloud container node-pools list --cluster "$CLUSTER_NAME" --zone "$CLUSTER_LOCATION" --project "$PROJECT_ID"
run 05-nodes kubectl get nodes -o wide
run 06-nodes-describe kubectl describe nodes
run 07-namespaces kubectl get ns
run 08-daemonsets kubectl get ds -A -o wide
run 09-deploy-sts kubectl get deploy,statefulset -A -o wide
run 10-pods-all kubectl get pods -A -o wide
run 11-pods-not-running kubectl get pods -A --field-selector=status.phase!=Running -o wide
run 12-pdb kubectl get pdb -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,MIN:.spec.minAvailable,MAX:.spec.maxUnavailable,ALLOWED:.status.disruptionsAllowed,EXPECTED:.status.expectedPods,CURRENT:.status.currentHealthy,DESIRED:.status.desiredHealthy
run 13-storage kubectl get storageclass,pv,pvc -A
run 14-resourcequota-limits kubectl get resourcequota,limitrange -A
run 15-networkpolicy kubectl get networkpolicy -A
run 16-webhooks kubectl get mutatingwebhookconfigurations,validatingwebhookconfigurations
run 17-crds kubectl get crd
run 18-serviceaccounts kubectl get sa -A
run 19-events kubectl get events -A --sort-by=.metadata.creationTimestamp
run 20-top-nodes kubectl top nodes
run 21-top-pods kubectl top pods -A --sort-by=cpu

echo
echo "Listo. Archivos generados en: $OUT"
echo
ls -1 "$OUT"
