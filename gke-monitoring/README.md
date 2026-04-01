# Datadog en GKE con Secret Manager Sync + Datadog Operator + Kustomize

## Objetivo

Implementar Datadog en GKE de forma simple, ordenada y reusable, usando:

- Google Secret Manager
- Secret Sync de GKE
- Datadog Operator
- Kustomize
- Namespace dedicado

Este documento está escrito **paso a paso para dummies**, con:

- qué hacer
- qué pegar
- qué revisar
- qué resultado esperar
- qué errores pueden aparecer
- cómo dejar la estructura lista para futuro `qa` y `prod`

---

# 1. Contexto actual

## Clúster actual

- **Project ID:** `gcp-fui-dev`
- **Cluster:** `gke-fui-dev-cl`
- **Location:** `southamerica-west1-a`
- **Datadog site:** `us5.datadoghq.com`

## Namespace elegido para Datadog en dev

- **Namespace:** `datadog-monitoring-dev`

## Secreto usado en Secret Manager

- **Secret:** `apikey_datadog_dev`

## Decisión importante

Hoy los ambientes `dev`, `qa` y `prod` existen como **namespaces** dentro del mismo clúster.

Por eso:

- **sí** dejamos overlays `dev`, `qa`, `prod` preparados en el repo
- **pero no** se deben desplegar tres Datadog Agents en este mismo clúster
- **Datadog se despliega por clúster**, no por namespace

---

# 2. Idea general de la solución

La solución queda así:

**Secret Manager -> SecretProviderClass -> SecretSync -> Kubernetes Secret (`datadog-secret`) -> DatadogAgent**

Y luego:

**Datadog Operator -> crea Datadog Agent (DaemonSet) + Cluster Agent (Deployment)**

---

# 3. Qué se decidió activar y qué no

## Fase 1: instalación mínima

Se deja activado solo esto:

- `clusterChecks: true`
- `orchestratorExplorer: false`

## No se activa todavía

Por ahora **no** se activa:

- APM
- Logs
- OTel Collector
- Universal Service Monitoring
- Profiling
- ASM / security features
- Autoscaling integration

La idea es validar primero la base sin meter carga innecesaria.

---

# 4. Estructura final del repo

La estructura recomendada es esta:

```text
gke-monitoring/
  README.md
  collect-gke-datadog-precheck.sh
  base/
    datadog-agent.yaml
    kustomization.yaml
    serviceaccount.yaml
  overlays/
    dev/
      namespace.yaml
      datadog-agent-patch.yaml
      secretproviderclass.yaml
      secretsync.yaml
      kustomization.yaml
    qa/
      namespace.yaml
      datadog-agent-patch.yaml
      kustomization.yaml
    prod/
      namespace.yaml
      datadog-agent-patch.yaml
      kustomization.yaml

5. Archivos YAML del repo
5.1 Base
gke-monitoring/base/serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: datadog-secret-sync
gke-monitoring/base/datadog-agent.yaml
apiVersion: datadoghq.com/v2alpha1
kind: DatadogAgent
metadata:
  name: datadog
spec:
  global:
    clusterName: CHANGE_ME
    site: us5.datadoghq.com
    registry: registry.datadoghq.com
    credentials:
      apiSecret:
        secretName: datadog-secret
        keyName: api-key

  features:
    clusterChecks:
      enabled: true
    orchestratorExplorer:
      enabled: false
gke-monitoring/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - serviceaccount.yaml
  - datadog-agent.yaml
5.2 Overlay dev
gke-monitoring/overlays/dev/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: datadog-monitoring-dev
  labels:
    app.kubernetes.io/name: datadog-monitoring-dev
    app.kubernetes.io/part-of: datadog
gke-monitoring/overlays/dev/datadog-agent-patch.yaml

Nota:
Como hoy dev, qa y prod conviven en el mismo clúster,
no conviene dejar env:dev como tag global del Agent.

Si en el futuro dev queda en un clúster propio, ese tag se puede volver a agregar.

apiVersion: datadoghq.com/v2alpha1
kind: DatadogAgent
metadata:
  name: datadog
spec:
  global:
    clusterName: gke-fui-dev-cl
    tags:
      - project:fui
      - region:cl
      - platform:gke
      - cluster_name:gke-fui-dev-cl
gke-monitoring/overlays/dev/secretproviderclass.yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: datadog-api-sm
spec:
  provider: gke
  parameters:
    secrets: |
      - resourceName: "projects/gcp-fui-dev/secrets/apikey_datadog_dev/versions/1"
        path: "api-key"
gke-monitoring/overlays/dev/secretsync.yaml
apiVersion: secret-sync.gke.io/v1
kind: SecretSync
metadata:
  name: datadog-secret
spec:
  serviceAccountName: datadog-secret-sync
  secretProviderClassName: datadog-api-sm
  secretObject:
    type: Opaque
    data:
      - sourcePath: "api-key"
        targetKey: "api-key"
gke-monitoring/overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: datadog-monitoring-dev

resources:
  - ../../base
  - namespace.yaml
  - secretproviderclass.yaml
  - secretsync.yaml

patches:
  - path: datadog-agent-patch.yaml
    target:
      kind: DatadogAgent
      name: datadog
5.3 Overlay qa

Este overlay queda preparado para futuro uso.
No aplicar mientras qa siga dentro del mismo clúster compartido.

gke-monitoring/overlays/qa/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: datadog-monitoring-qa
  labels:
    app.kubernetes.io/name: datadog-monitoring-qa
    app.kubernetes.io/part-of: datadog
gke-monitoring/overlays/qa/datadog-agent-patch.yaml
apiVersion: datadoghq.com/v2alpha1
kind: DatadogAgent
metadata:
  name: datadog
spec:
  global:
    clusterName: CHANGE_ME_QA
    tags:
      - env:qa
      - project:fui
      - region:cl
      - platform:gke
      - cluster_name:CHANGE_ME_QA
gke-monitoring/overlays/qa/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: datadog-monitoring-qa

resources:
  - ../../base
  - namespace.yaml

patches:
  - path: datadog-agent-patch.yaml
    target:
      kind: DatadogAgent
      name: datadog
5.4 Overlay prod

Este overlay queda preparado para cuando exista un clúster separado de prod.

gke-monitoring/overlays/prod/namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: datadog-monitoring-prod
  labels:
    app.kubernetes.io/name: datadog-monitoring-prod
    app.kubernetes.io/part-of: datadog
gke-monitoring/overlays/prod/datadog-agent-patch.yaml
apiVersion: datadoghq.com/v2alpha1
kind: DatadogAgent
metadata:
  name: datadog
spec:
  global:
    clusterName: CHANGE_ME_PROD
    tags:
      - env:prod
      - project:fui
      - region:cl
      - platform:gke
      - cluster_name:CHANGE_ME_PROD
gke-monitoring/overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: datadog-monitoring-prod

resources:
  - ../../base
  - namespace.yaml

patches:
  - path: datadog-agent-patch.yaml
    target:
      kind: DatadogAgent
      name: datadog
6. Prerrequisitos

Antes de partir, necesitas:

gcloud
kubectl
helm
acceso al proyecto gcp-fui-dev
acceso al clúster gke-fui-dev-cl
Workload Identity habilitado
Secret Manager add-on habilitado
Secret Sync habilitado
secreto apikey_datadog_dev creado en Secret Manager
7. Variables base

Pega esto en terminal:

export PROJECT_ID="gcp-fui-dev"
export CLUSTER_NAME="gke-fui-dev-cl"
export CLUSTER_LOCATION="southamerica-west1-a"

gcloud config set project "$PROJECT_ID"

gcloud container clusters get-credentials "$CLUSTER_NAME" \
  --zone "$CLUSTER_LOCATION" \
  --project "$PROJECT_ID"
Check esperado
kubectl config current-context
kubectl get nodes -o wide
kubectl version --client

Debes ver:

contexto del clúster correcto
nodos del clúster
cliente kubectl funcionando
8. Verificar que el clúster tiene Secret Manager + Secret Sync

Pega esto:

gcloud beta container clusters describe "$CLUSTER_NAME" \
  --location "$CLUSTER_LOCATION" \
  --project "$PROJECT_ID" \
  --format="yaml(secretManagerConfig,secretSyncConfig,workloadIdentityConfig)"
Check esperado

Debes ver:

secretManagerConfig.enabled: true
secretSyncConfig.enabled: true
workloadIdentityConfig.workloadPool presente
9. Dar permiso IAM al secreto de Datadog

El secreto de Datadog está en Secret Manager:

apikey_datadog_dev

La cuenta que debe leerlo es:

namespace: datadog-monitoring-dev
service account: datadog-secret-sync

Pega esto:

PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

gcloud secrets add-iam-policy-binding apikey_datadog_dev \
  --project="$PROJECT_ID" \
  --role="roles/secretmanager.secretAccessor" \
  --member="principal://iam.googleapis.com/projects/${PROJECT_NUMBER}/locations/global/workloadIdentityPools/${PROJECT_ID}.svc.id.goog/subject/ns/datadog-monitoring-dev/sa/datadog-secret-sync"
Check esperado

El comando debe responder con Updated IAM policy.

10. Crear recursos para Secret Manager Sync
Paso 10.1 Crear namespace
kubectl apply -f gke-monitoring/overlays/dev/namespace.yaml
Check esperado
kubectl get ns datadog-monitoring-dev

Debe existir el namespace.

Paso 10.2 Crear ServiceAccount
kubectl apply -f gke-monitoring/base/serviceaccount.yaml -n datadog-monitoring-dev
Check esperado
kubectl get sa -n datadog-monitoring-dev

Debe aparecer datadog-secret-sync.

Paso 10.3 Crear SecretProviderClass
kubectl apply -f gke-monitoring/overlays/dev/secretproviderclass.yaml -n datadog-monitoring-dev
Check esperado
kubectl get secretproviderclass -n datadog-monitoring-dev

Debe aparecer datadog-api-sm.

Paso 10.4 Crear SecretSync
kubectl apply -f gke-monitoring/overlays/dev/secretsync.yaml -n datadog-monitoring-dev
Check esperado
kubectl get secretsync -n datadog-monitoring-dev

Debe aparecer datadog-secret.

11. Validar que el secret de Kubernetes fue creado

Pega esto:

kubectl describe secretsync datadog-secret -n datadog-monitoring-dev
kubectl get secret datadog-secret -n datadog-monitoring-dev
kubectl get secret datadog-secret -n datadog-monitoring-dev -o jsonpath='{.type}{"\n"}'
kubectl get secret datadog-secret -n datadog-monitoring-dev -o jsonpath='{.data.api-key}' | wc -c
Resultado esperado
SecretSync con mensajes tipo:
Secret created successfully
UpdateNoValueChangeSucceeded
datadog-secret existe
tipo Opaque
longitud mayor que 0 para .data.api-key

Importante:
No imprimir el valor del secret completo en pantalla salvo que sea estrictamente necesario.

12. Instalar Helm

Si no está instalado:

sudo snap install helm --classic
helm version
Check esperado

helm version responde correctamente.

13. Instalar Datadog Operator

Pega esto:

helm repo add datadog https://helm.datadoghq.com
helm repo update

helm install datadog-operator datadog/datadog-operator \
  --namespace datadog-monitoring-dev
Check esperado

El comando termina con algo como:

STATUS: deployed
14. Validar Datadog Operator

Pega esto:

kubectl get crd | grep datadoghq.com || true
kubectl get deploy,pods -n datadog-monitoring-dev -o wide
kubectl wait --for=condition=available deployment --all -n datadog-monitoring-dev --timeout=180s
kubectl get all -n datadog-monitoring-dev
Resultado esperado

Debes ver:

CRDs de datadoghq.com
deployment/datadog-operator
pod del operator Running
15. Render de Kustomize antes de aplicar el Agent

Siempre conviene revisar primero:

kubectl kustomize gke-monitoring/overlays/dev | sed -n '1,260p'
Check esperado

Debes ver:

Namespace datadog-monitoring-dev
ServiceAccount datadog-secret-sync
SecretProviderClass datadog-api-sm
SecretSync datadog-secret
DatadogAgent
clusterName: gke-fui-dev-cl
16. Aplicar el DatadogAgent

Pega esto:

kubectl apply -k gke-monitoring/overlays/dev
Check esperado

Debes ver algo parecido a:

datadogagent.datadoghq.com/datadog created

17. Validar que el DatadogAgent fue creado

Pega esto:

kubectl get datadogagent -n datadog-monitoring-dev
kubectl describe datadogagent datadog -n datadog-monitoring-dev
Resultado esperado

Primero lo verás en creación, luego terminará mostrando algo como:

AGENT Running
CLUSTER-AGENT Running

18. Validar recursos creados por el Operator

Pega esto:

kubectl get ds,deploy,svc -n datadog-monitoring-dev
kubectl get pods -n datadog-monitoring-dev -o wide
Resultado esperado

Debes ver:

deployment/datadog-operator
deployment/datadog-cluster-agent
daemonset/datadog-agent
1 pod del operator
1 pod del cluster agent
1 pod del agent por nodo

Como hoy el clúster tiene 2 nodos, lo normal es ver:

2 pods datadog-agent
1 pod datadog-cluster-agent
1 pod datadog-operator

19. Esperar a que termine el rollout

Pega esto:

kubectl wait --for=condition=available deployment --all -n datadog-monitoring-dev --timeout=180s

kubectl get ds -n datadog-monitoring-dev

kubectl rollout status daemonset -n datadog-monitoring-dev $(kubectl get ds -n datadog-monitoring-dev -o jsonpath='{.items[0].metadata.name}') --timeout=180s
Resultado esperado
Deployments Available
DaemonSet con rollout exitoso

20. Validar consumo y eventos

Pega esto:

kubectl top pods -n datadog-monitoring-dev
kubectl get events -n datadog-monitoring-dev --sort-by=.metadata.creationTimestamp | tail -50
Resultado esperado
Pods Running
Sin CrashLoopBackOff
Sin errores críticos persistentes

21. Validación final

Pega esto:

kubectl get datadogagent -n datadog-monitoring-dev
kubectl get ds,deploy,svc -n datadog-monitoring-dev
kubectl get pods -n datadog-monitoring-dev -o wide
kubectl top pods -n datadog-monitoring-dev
Resultado esperado final
DatadogAgent = Running
datadog-agent DaemonSet = 2/2
datadog-cluster-agent = 1/1
datadog-operator = 1/1

22. Estado real observado en esta implementación

Se validó:

DatadogAgent = Running
datadog-agent = 2/2
datadog-cluster-agent = 1/1
datadog-operator = 1/1
Consumo aproximado observado
datadog-agent -> entre ~53m y ~180m CPU, ~135Mi a ~143Mi RAM
datadog-cluster-agent -> ~11m CPU, ~94Mi RAM
datadog-operator -> ~2m CPU, ~52Mi RAM
23. Troubleshooting básico

Caso 1: SecretSync no existe

Síntoma:

error al aplicar secretsync.yaml
mensaje tipo:
no matches for kind "SecretSync"

Qué revisar:

gcloud beta container clusters describe "$CLUSTER_NAME" \
  --location "$CLUSTER_LOCATION" \
  --project "$PROJECT_ID" \
  --format="yaml(secretManagerConfig,secretSyncConfig,workloadIdentityConfig)"

Si secretSyncConfig.enabled no está en true, habilitar:

gcloud beta container clusters update "$CLUSTER_NAME" \
  --location "$CLUSTER_LOCATION" \
  --project "$PROJECT_ID" \
  --enable-secret-sync

Luego validar:

kubectl api-resources | grep -i secretsync || true

Caso 2: el secret no aparece en Kubernetes

Qué revisar:

kubectl describe secretsync datadog-secret -n datadog-monitoring-dev
kubectl get secret datadog-secret -n datadog-monitoring-dev

También revisar:

IAM del secreto en Secret Manager
namespace correcto
service account correcta
secret provider class correcto

Caso 3: Helm no existe

Instalar:

sudo snap install helm --classic
helm version

Caso 4: DatadogAgent no levanta

Revisar:

kubectl describe datadogagent datadog -n datadog-monitoring-dev
kubectl get pods -n datadog-monitoring-dev -o wide
kubectl get events -n datadog-monitoring-dev --sort-by=.metadata.creationTimestamp | tail -50
kubectl logs deployment/datadog-operator -n datadog-monitoring-dev --tail=200

Caso 5: aparece un warning de NEG en eventos

En la implementación actual aparecieron warnings tipo:

ProcessServiceFailed
servicenetworkendpointgroups.networking.gke.io ... already exists

Mientras todo quede finalmente en:

DatadogAgent Running
DaemonSet Running
Cluster Agent Running

eso se considera un warning transitorio y no necesariamente un error bloqueante.

24. Qué no se debe hacer ahora

No activar todavía:

APM
Logs
OTel Collector
Universal Service Monitoring
Profiling
ASM / security features
Autoscaling integration

Primero dejar estable la base.

25. Qué hacer con qa y prod
No desplegar qa y prod en este mismo clúster

Aunque hoy existan como namespaces, no corresponde instalar otro Datadog Agent adicional por cada namespace.

La unidad correcta es el clúster, no el namespace.

Sí dejar qa y prod listos en el repo

Los overlays quedan preparados para futuro uso.

Cuándo sí usar qa o prod

Cuando exista un clúster realmente separado, por ejemplo:

gke-fui-qa-cl
gke-fui-prod-cl

Ahí sí:

usar el overlay correspondiente
crear secreto específico del ambiente
crear IAM binding específico del ambiente
crear namespace específico del ambiente
desplegar Datadog en ese clúster

26. Importante sobre tags

Como hoy el mismo clúster contiene dev, qa y prod, no conviene dejar env:dev como tag global del Agent.

Por eso, el patch actual de dev no lleva env:dev.

Cuando dev tenga un clúster propio, ese tag se puede volver a agregar.

27. Limpieza realizada

Se eliminó el namespace inicial incorrecto:

kubectl delete namespace datadog-monitoring
28. Comandos útiles de soporte
Ver recursos de Datadog
kubectl get datadogagent -n datadog-monitoring-dev
kubectl get ds,deploy,svc -n datadog-monitoring-dev
kubectl get pods -n datadog-monitoring-dev -o wide
Ver eventos recientes
kubectl get events -n datadog-monitoring-dev --sort-by=.metadata.creationTimestamp | tail -50
Ver consumo
kubectl top pods -n datadog-monitoring-dev
kubectl top nodes
Ver logs del Operator
kubectl logs deployment/datadog-operator -n datadog-monitoring-dev --tail=200
Ver DatadogAgent en detalle
kubectl describe datadogagent datadog -n datadog-monitoring-dev
29. Próximos pasos recomendados
Fase 2

Evaluar más adelante, con calma, si activar:

orchestratorExplorer
logs selectivos
APM solo para workloads definidos
tags por workload o namespace
Futuro clúster prod

Cuando exista un clúster dedicado a prod:

usar overlays/prod
crear secreto apikey_datadog_prod
crear IAM binding para datadog-monitoring-prod
desplegar Datadog en ese clúster
30. Resumen final

La instalación base de Datadog en GKE dev quedó:

con namespace dedicado
con Secret Manager Sync funcionando
con Datadog Operator instalado
con Datadog Agent desplegado
con repo reusable preparado para futuro qa y prod

La base quedó estable, mínima y lista para evolucionar.