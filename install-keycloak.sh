#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="keycloak"
KEYCLOAK_VERSION="26.6.2"

ADMIN_USER="admin"
ADMIN_PASSWORD="admin"

REALM="openshift"
CLIENT_ID="openshift"

echo "========================================="
echo "Installing Keycloak ${KEYCLOAK_VERSION}"
echo "========================================="

echo
echo "[1/9] Creating project..."
oc new-project ${NAMESPACE} 2>/dev/null || true

echo
echo "[2/9] Deploying Keycloak..."
oc new-app quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} \
  --name=keycloak \
  -n ${NAMESPACE}

echo
echo "[3/9] Configuring Keycloak..."

oc set env deployment/keycloak \
  KC_BOOTSTRAP_ADMIN_USERNAME=${ADMIN_USER} \
  KC_BOOTSTRAP_ADMIN_PASSWORD=${ADMIN_PASSWORD} \
  KC_HTTP_ENABLED=true \
  KC_PROXY_HEADERS=xforwarded \
  -n ${NAMESPACE}

echo
echo "[4/9] Setting startup command..."

oc patch deployment keycloak \
  -n ${NAMESPACE} \
  --type=json \
  -p='[
    {
      "op":"add",
      "path":"/spec/template/spec/containers/0/args",
      "value":["start-dev"]
    }
  ]'

echo
echo "[5/9] Waiting for deployment..."

oc rollout restart deployment/keycloak -n ${NAMESPACE}
oc rollout status deployment/keycloak -n ${NAMESPACE} --timeout=300s

echo
echo "[6/9] Creating route..."

oc delete route keycloak -n ${NAMESPACE} --ignore-not-found

oc create route edge keycloak \
  --service=keycloak \
  --port=8080-tcp \
  -n ${NAMESPACE}

sleep 5

KEYCLOAK_HOST=$(oc get route keycloak -n ${NAMESPACE} -o jsonpath='{.spec.host}')

echo
echo "[7/9] Exporting route certificate..."

openssl s_client \
  -connect ${KEYCLOAK_HOST}:443 \
  -showcerts < /dev/null 2>/dev/null \
| sed -n '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/p' \
> keycloak.crt

echo
echo "[8/9] Creating OpenShift CA configmap..."

oc create configmap keycloak-ca \
  --from-file=ca-bundle.crt=keycloak.crt \
  -n openshift-config \
  --dry-run=client -o yaml | oc apply -f -

echo
echo "[9/9] Done"

echo
echo "========================================="
echo "KEYCLOAK INSTALLED"
echo "========================================="
echo
echo "URL:"
echo "https://${KEYCLOAK_HOST}"
echo
echo "Admin username: ${ADMIN_USER}"
echo "Admin password: ${ADMIN_PASSWORD}"
echo
echo "========================================="
echo "NEXT STEPS"
echo "========================================="
echo
echo "1. Login to Keycloak"
echo
echo "2. Create realm:"
echo "   ${REALM}"
echo
echo "3. Create client:"
echo "   Client ID: ${CLIENT_ID}"
echo "   Client authentication: ON"
echo
echo "4. Valid Redirect URI:"
echo "   https://oauth-openshift.apps-crc.testing/oauth2callback/keycloak/*"
echo
echo "5. Create test user"
echo
echo "6. Copy client secret"
echo
echo "7. Create OpenShift secret:"
echo
cat <<EOF
oc create secret generic keycloak-secret \\
  --from-literal=clientSecret=<CLIENT_SECRET> \\
  -n openshift-config
EOF

echo
echo "8. Configure OpenShift OAuth:"
echo

cat <<EOF
oc apply -f - <<YAML
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: keycloak
    mappingMethod: claim
    type: OpenID
    openID:
      clientID: openshift
      clientSecret:
        name: keycloak-secret
      issuer: https://${KEYCLOAK_HOST}/realms/${REALM}
      ca:
        name: keycloak-ca
      claims:
        preferredUsername:
        - preferred_username
        name:
        - name
        email:
        - email
YAML
EOF

echo
echo "9. Watch authentication operator:"
echo
echo "watch oc get co authentication"
