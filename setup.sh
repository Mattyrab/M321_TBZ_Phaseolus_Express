#!/usr/bin/env bash
#
# Sets up the Phaseolus Express architecture (docs/plans/2026_09_phaseolus-architecture/)
# from scratch on a new Linux system: minikube cluster, infra (RabbitMQ, Keycloak,
# Traefik, Prometheus/Grafana), the five service repos built and deployed, Argo CD
# wired up as the App-of-Apps per Step 13 of the plan.
#
# Run this FROM a checkout of this meta repo (it clones the five service repos as
# sibling directories next to itself). Requires a GitHub token with repo access to
# this (private) meta repo -- pass it as GITHUB_TOKEN, or have `gh auth login` already
# done so `gh auth token` can supply one.
#
# Infra scope note: per the plan's Step 13 incident writeup, the four infra Helm
# charts are intentionally NOT Argo CD-managed -- they're installed here directly via
# helm and stay that way. Only the five services + this repo's own k8s/infra/
# manifests are GitOps-managed.
set -euo pipefail

MINIKUBE_CPUS="${MINIKUBE_CPUS:-4}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-8192}"
GITHUB_USERNAME="${GITHUB_USERNAME:-Mattyrab}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-phaseolus}"
RABBITMQ_PASSWORD="${RABBITMQ_PASSWORD:-phaseolus}"
GRAFANA_PASSWORD="${GRAFANA_PASSWORD:-phaseolus}"
ADMIN_UI_CLIENT_SECRET="${ADMIN_UI_CLIENT_SECRET:-phaseolus}"
RABBITMQ_CLIENT_SECRET="${RABBITMQ_CLIENT_SECRET:-phaseolus}"

META_REPO_URL="https://github.com/${GITHUB_USERNAME}/M321_TBZ_Phaseolus_Express.git"
UPSTREAM_OWNER="Timposter8107"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

log() { echo -e "\n=== $1 ===\n"; }

# ---------------------------------------------------------------------------
# 1. Prerequisites
# ---------------------------------------------------------------------------
log "Checking prerequisites"

install_if_missing() {
  local cmd="$1" apt_pkg="$2"
  if ! command -v "$cmd" &>/dev/null; then
    echo "Installing $cmd..."
    sudo apt-get update -qq && sudo apt-get install -y -qq "$apt_pkg"
  fi
}

if ! command -v docker &>/dev/null; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "Docker installed. If this is the first install, log out/in (or run 'newgrp docker') and re-run this script."
  exit 0
fi

install_if_missing git git
install_if_missing jq jq
install_if_missing curl curl

if ! command -v kubectl &>/dev/null; then
  echo "Installing kubectl..."
  curl -fsSLO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
  rm -f kubectl
fi

if ! command -v minikube &>/dev/null; then
  echo "Installing minikube..."
  curl -fsSLo minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"
  sudo install minikube /usr/local/bin/minikube
  rm -f minikube
fi

if ! command -v helm &>/dev/null; then
  echo "Installing Helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if ! command -v gh &>/dev/null; then
  echo "Installing GitHub CLI..."
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update -qq && sudo apt-get install -y -qq gh
fi

if [ -z "$GITHUB_TOKEN" ] && command -v gh &>/dev/null; then
  GITHUB_TOKEN="$(gh auth token 2>/dev/null || true)"
fi
if [ -z "$GITHUB_TOKEN" ]; then
  echo "ERROR: no GitHub token available. Set GITHUB_TOKEN, or run 'gh auth login' first." >&2
  echo "A token is needed to register this private meta repo with Argo CD." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Cluster
# ---------------------------------------------------------------------------
log "Starting minikube (--cpus=$MINIKUBE_CPUS --memory=$MINIKUBE_MEMORY)"
minikube start --driver=docker --cpus="$MINIKUBE_CPUS" --memory="$MINIKUBE_MEMORY"

kubectl create namespace phaseolus --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace infra --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------------------
# 3. Infra (manually Helm-managed -- see Step 13's incident writeup for why)
# ---------------------------------------------------------------------------
log "Installing infra Helm charts"

helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null
helm repo add traefik https://traefik.github.io/charts >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo update >/dev/null

helm upgrade --install rabbitmq bitnami/rabbitmq -n infra --version 16.0.14 \
  --set auth.username=phaseolus \
  --set auth.password="$RABBITMQ_PASSWORD" \
  --set global.security.allowInsecureImages=true \
  --set image.repository=bitnamilegacy/rabbitmq \
  --set volumePermissions.image.repository=bitnamilegacy/os-shell \
  --set-string extraConfiguration="prometheus.return_per_object_metrics = true" \
  --set resourcesPreset=large

helm upgrade --install keycloak bitnami/keycloak -n infra --version 25.2.0 \
  --set auth.adminUser=admin \
  --set auth.adminPassword="$KEYCLOAK_ADMIN_PASSWORD" \
  --set global.security.allowInsecureImages=true \
  --set image.repository=bitnamilegacy/keycloak \
  --set keycloakConfigCli.image.repository=bitnamilegacy/keycloak-config-cli \
  --set postgresql.image.repository=bitnamilegacy/postgresql \
  --set postgresql.volumePermissions.image.repository=bitnamilegacy/os-shell \
  --set postgresql.metrics.image.repository=bitnamilegacy/postgres-exporter \
  --set resourcesPreset=large \
  --set startupProbe.enabled=true \
  --set startupProbe.initialDelaySeconds=10 \
  --set startupProbe.periodSeconds=10 \
  --set startupProbe.failureThreshold=30

helm upgrade --install traefik traefik/traefik -n infra --version 41.6.1

# SSO admin-uis plan Step 2: Grafana's generic_oauth has separate auth_url
# (browser-facing, via the keycloak port-forward) vs token_url/api_url
# (in-cluster DNS, reached by Grafana's own backend) -- same Authority vs
# PublicAuthority split the sso-keycloak plan hit for BeanApp/BeanNotifs, but
# Grafana supports it natively as distinct config keys. Per Q4, no
# role_attribute_path restriction: any successful Keycloak login is admitted.
# client_secret is passed via $__env{} + a plain env var, not inlined in
# grafana.ini, because the chart's assertNoLeakedSecrets check refuses to
# template a literal secret value into grafana.ini directly.
cat > /tmp/phaseolus-grafana-oauth-values.yaml <<EOF
grafana:
  env:
    GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET: "$ADMIN_UI_CLIENT_SECRET"
  grafana.ini:
    auth.generic_oauth:
      enabled: true
      name: Keycloak
      client_id: admin-ui-client
      client_secret: \$__env{GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET}
      scopes: openid email profile
      auth_url: http://localhost:8180/realms/phaseolus/protocol/openid-connect/auth
      token_url: http://keycloak.infra.svc.cluster.local/realms/phaseolus/protocol/openid-connect/token
      api_url: http://keycloak.infra.svc.cluster.local/realms/phaseolus/protocol/openid-connect/userinfo
      allow_sign_up: true
EOF

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -n infra --version 91.8.2 \
  -f /tmp/phaseolus-grafana-oauth-values.yaml \
  --set grafana.adminPassword="$GRAFANA_PASSWORD"

log "Waiting for RabbitMQ and Keycloak to be ready"
kubectl wait --for=condition=Ready pod/rabbitmq-0 -n infra --timeout=180s
kubectl wait --for=condition=Ready pod/keycloak-postgresql-0 -n infra --timeout=180s
kubectl wait --for=condition=Ready pod/keycloak-0 -n infra --timeout=240s

# ---------------------------------------------------------------------------
# 4. Argo CD
# ---------------------------------------------------------------------------
log "Installing Argo CD"
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# --server-side: the applicationsets CRD exceeds kubectl's client-side annotation
# size limit for a plain `kubectl apply`.
kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s

kubectl create secret generic repo-meta-phaseolus -n argocd \
  --from-literal=type=git \
  --from-literal=url="$META_REPO_URL" \
  --from-literal=username="$GITHUB_USERNAME" \
  --from-literal=password="$GITHUB_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl label secret repo-meta-phaseolus -n argocd argocd.argoproj.io/secret-type=repository --overwrite

# ---------------------------------------------------------------------------
# 5. Clone, build, and load the five service images
# ---------------------------------------------------------------------------
log "Cloning and building the five services"

declare -A REPO_IMAGE=(
  [M321_TBZ_Phaseolus_Order]=orderbeans
  [M321_TBZ_Phaseolus_Pay]=paybeancoins
  [M321_TBZ_Phaseolus_Cooker]=cookerbeaners
  [M321_TBZ_Phaseolus_Notifs]=beannotifs
  [M321_TBZ_Phaseolus_WebApp]=beanapp
)

for repo in "${!REPO_IMAGE[@]}"; do
  image="${REPO_IMAGE[$repo]}"
  if [ ! -d "$repo" ]; then
    git clone "https://github.com/${UPSTREAM_OWNER}/${repo}.git" "$repo"
  fi
  docker build -t "${image}:dev" "$repo"
  minikube image load "${image}:dev"
done

# ---------------------------------------------------------------------------
# 6. Keycloak realm/client -- secret pinned to what's already committed in
#    BeanApp's deploy manifest, so Argo CD can deploy it unmodified.
# ---------------------------------------------------------------------------
log "Configuring Keycloak realm and client"

kubectl -n infra port-forward svc/keycloak 18081:80 >/tmp/phaseolus-setup-keycloak-pf.log 2>&1 &
KC_PF_PID=$!
trap 'kill $KC_PF_PID 2>/dev/null || true' EXIT
sleep 5

ADMIN_TOKEN=$(curl -s -X POST http://localhost:18081/realms/master/protocol/openid-connect/token \
  -d "grant_type=password" -d "client_id=admin-cli" -d "username=admin" -d "password=$KEYCLOAK_ADMIN_PASSWORD" \
  | jq -r .access_token)

BEANAPP_SECRET=$(grep -A1 "Keycloak__ClientSecret" M321_TBZ_Phaseolus_WebApp/deploy/deployment.yaml | tail -1 | sed 's/.*value: *//')

curl -s -o /dev/null -w "realm create: %{http_code}\n" \
  -X POST http://localhost:18081/admin/realms \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"realm":"phaseolus","enabled":true}'

curl -s -o /dev/null -w "client create: %{http_code}\n" \
  -X POST http://localhost:18081/admin/realms/phaseolus/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg secret "$BEANAPP_SECRET" '{
    clientId: "beanapp-client",
    protocol: "openid-connect",
    publicClient: false,
    serviceAccountsEnabled: true,
    standardFlowEnabled: true,
    directAccessGrantsEnabled: false,
    authorizationServicesEnabled: false,
    enabled: true,
    secret: $secret,
    redirectUris: ["*"],
    webOrigins: ["*"],
    attributes: { "post.logout.redirect.uris": "+" }
  }')"

# Admin-login feature: a realm role + demo user so the BeanApp Admin page
# (view-only orders/payments/notifications log) has someone to log in as.
curl -s -o /dev/null -w "admin role create: %{http_code}\n" \
  -X POST http://localhost:18081/admin/realms/phaseolus/roles \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{"name":"admin","description":"Phaseolus Express admin role"}'

curl -s -o /dev/null -w "admin user create: %{http_code}\n" \
  -X POST http://localhost:18081/admin/realms/phaseolus/users \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "enabled": true,
    "emailVerified": true,
    "email": "admin@phaseolus.local",
    "firstName": "Phaseolus",
    "lastName": "Admin",
    "credentials": [{"type": "password", "value": "phaseolus", "temporary": false}]
  }'

ADMIN_ROLE=$(curl -s http://localhost:18081/admin/realms/phaseolus/roles/admin \
  -H "Authorization: Bearer $ADMIN_TOKEN")
ADMIN_USER_ID=$(curl -s "http://localhost:18081/admin/realms/phaseolus/users?username=admin&exact=true" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')

curl -s -o /dev/null -w "admin role assign: %{http_code}\n" \
  -X POST "http://localhost:18081/admin/realms/phaseolus/users/$ADMIN_USER_ID/role-mappings/realm" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "[$ADMIN_ROLE]"

# By default Keycloak only puts realm_access.roles on the access token, not the ID
# token -- BeanApp's OIDC login reads roles off the ID token, so without this fix
# the admin role never shows up there and [Authorize(Roles = "admin")] always fails.
ROLES_SCOPE_ID=$(curl -s http://localhost:18081/admin/realms/phaseolus/client-scopes \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[] | select(.name=="roles") | .id')
REALM_ROLES_MAPPER=$(curl -s "http://localhost:18081/admin/realms/phaseolus/client-scopes/$ROLES_SCOPE_ID/protocol-mappers/models" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -c '.[] | select(.name=="realm roles")')
REALM_ROLES_MAPPER_ID=$(echo "$REALM_ROLES_MAPPER" | jq -r '.id')
echo "$REALM_ROLES_MAPPER" | jq '.config["id.token.claim"] = "true"' > /tmp/phaseolus-realm-roles-mapper.json
curl -s -o /dev/null -w "realm-roles-in-id-token fix: %{http_code}\n" \
  -X PUT "http://localhost:18081/admin/realms/phaseolus/client-scopes/$ROLES_SCOPE_ID/protocol-mappers/models/$REALM_ROLES_MAPPER_ID" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d @/tmp/phaseolus-realm-roles-mapper.json

# SSO plan Step 1: every token beanapp-client issues (interactive login or
# client-credentials) carries a shared audience, so OrderBeans/BeanNotifs can
# check "was this token meant for one of our services" instead of just "is it
# signed by our realm."
BEANAPP_CLIENT_UUID=$(curl -s "http://localhost:18081/admin/realms/phaseolus/clients?clientId=beanapp-client" \
  -H "Authorization: Bearer $ADMIN_TOKEN" | jq -r '.[0].id')
curl -s -o /dev/null -w "audience mapper create: %{http_code}\n" \
  -X POST "http://localhost:18081/admin/realms/phaseolus/clients/$BEANAPP_CLIENT_UUID/protocol-mappers/models" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "name": "phaseolus-internal-api-audience",
    "protocol": "openid-connect",
    "protocolMapper": "oidc-audience-mapper",
    "config": {
      "included.custom.audience": "phaseolus-internal-api",
      "id.token.claim": "false",
      "access.token.claim": "true"
    }
  }'

# SSO admin-uis plan Step 1: a shared client for Grafana + Argo CD's own
# native OIDC logins (docs/plans/2026_10_sso-admin-uis/30_open_questions.md Q1),
# and a dedicated client for RabbitMQ's OAuth2 management-UI plugin (configured
# in a later step -- this just registers the client).
curl -s -o /dev/null -w "admin-ui-client create: %{http_code}\n" \
  -X POST http://localhost:18081/admin/realms/phaseolus/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg secret "$ADMIN_UI_CLIENT_SECRET" '{
    clientId: "admin-ui-client",
    protocol: "openid-connect",
    publicClient: false,
    serviceAccountsEnabled: false,
    standardFlowEnabled: true,
    directAccessGrantsEnabled: false,
    authorizationServicesEnabled: false,
    enabled: true,
    secret: $secret,
    redirectUris: ["http://localhost:3000/login/generic_oauth", "https://localhost:8443/auth/callback"],
    webOrigins: ["+"],
    attributes: { "post.logout.redirect.uris": "+" }
  }')"

curl -s -o /dev/null -w "rabbitmq-client create: %{http_code}\n" \
  -X POST http://localhost:18081/admin/realms/phaseolus/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d "$(jq -n --arg secret "$RABBITMQ_CLIENT_SECRET" '{
    clientId: "rabbitmq-client",
    protocol: "openid-connect",
    publicClient: false,
    serviceAccountsEnabled: false,
    standardFlowEnabled: true,
    directAccessGrantsEnabled: false,
    authorizationServicesEnabled: false,
    enabled: true,
    secret: $secret,
    redirectUris: ["http://localhost:15672/js/oidc-oauth/login-callback.html"],
    webOrigins: ["+"],
    attributes: { "post.logout.redirect.uris": "+" }
  }')"

# Longer-lived access tokens (default is 5 minutes) so a logged-in admin's
# session doesn't expire mid-use; see SSO plan Q3.
curl -s "http://localhost:18081/admin/realms/phaseolus" \
  -H "Authorization: Bearer $ADMIN_TOKEN" \
  | jq '.accessTokenLifespan = 900' > /tmp/phaseolus-realm-patch.json
curl -s -o /dev/null -w "realm access token lifespan: %{http_code}\n" \
  -X PUT "http://localhost:18081/admin/realms/phaseolus" \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H "Content-Type: application/json" \
  -d @/tmp/phaseolus-realm-patch.json

kill $KC_PF_PID 2>/dev/null || true
trap - EXIT

# ---------------------------------------------------------------------------
# 7. Bootstrap the Argo CD App-of-Apps (the one manual kubectl apply)
# ---------------------------------------------------------------------------
log "Bootstrapping Argo CD App-of-Apps"
kubectl apply -f k8s/argocd/root.yaml
kubectl apply -f k8s/infra/

log "Waiting for the five services to come up via Argo CD"

# `kubectl wait` only waits for a condition on a resource that already exists --
# it fails immediately with NotFound if Argo CD hasn't finished its first
# reconcile of phaseolus-root yet (which creates these Application objects).
# Poll for existence first, then wait for health.
wait_for_app_healthy() {
  local app="$1" timeout="${2:-180}" elapsed=0
  while ! kubectl get "application/$app" -n argocd &>/dev/null; do
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "WARNING: application/$app never appeared within ${timeout}s" >&2
      return 1
    fi
    sleep 3
    elapsed=$((elapsed + 3))
  done
  kubectl wait --for=jsonpath='{.status.health.status}'=Healthy "application/$app" -n argocd --timeout="${timeout}s" || true
}

for app in orderbeans paybeancoins cookerbeaners beannotifs beanapp; do
  wait_for_app_healthy "$app" 180
done

# ---------------------------------------------------------------------------
# 8. Port-forwards for manual browsing (BeanApp, monitoring, message queue)
# ---------------------------------------------------------------------------
log "Starting port-forwards for manual access"

PF_PID_FILE="$SCRIPT_DIR/.phaseolus-port-forwards.pid"
: > "$PF_PID_FILE"

start_port_forward() {
  local name="$1" namespace="$2" service="$3" ports="$4"
  nohup kubectl -n "$namespace" port-forward "svc/$service" "$ports" \
    >"/tmp/phaseolus-pf-${name}.log" 2>&1 &
  disown
  echo "${name}:$!" >> "$PF_PID_FILE"
}

start_port_forward beanapp    phaseolus beanapp 5050:8080
start_port_forward grafana    infra     prometheus-grafana 3000:80
start_port_forward rabbitmq   infra     rabbitmq 15672:15672
start_port_forward keycloak   infra     keycloak 8180:80
start_port_forward prometheus infra     prometheus-kube-prometheus-prometheus 9090:9090
start_port_forward argocd     argocd    argocd-server 8443:443
sleep 3

log "Done"
echo "Namespaces:"
kubectl get pods -n phaseolus
kubectl get pods -n infra
echo
echo "Argo CD Applications:"
kubectl get application -n argocd
echo
echo "Manual access (port-forwards running in the background -- PIDs in $PF_PID_FILE):"
echo "  BeanApp             http://localhost:5050   (Admin page login: admin / phaseolus)"
echo "  Grafana             http://localhost:3000   admin / $GRAFANA_PASSWORD"
echo "  RabbitMQ management http://localhost:15672   phaseolus / $RABBITMQ_PASSWORD"
echo "  Keycloak admin      http://localhost:8180    admin / $KEYCLOAK_ADMIN_PASSWORD (realm: master)"
echo "  Prometheus          http://localhost:9090"
echo "  Argo CD UI          https://localhost:8443   admin / \$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
echo
echo "To stop the port-forwards later:"
echo "  awk -F: '{print \$2}' $PF_PID_FILE | xargs -r kill"
echo
echo "To reach BeanApp via Traefik (the real ingress path) instead, run in a separate terminal:"
echo "  minikube service traefik -n infra --url"
