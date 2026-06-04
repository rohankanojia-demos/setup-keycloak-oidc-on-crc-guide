#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION VARIABLES ---
KEYCLOAK_HOST="keycloak-keycloak.apps-crc.testing"
KEYCLOAK_URL="https://${KEYCLOAK_HOST}/realms/openshift"
API_URL="https://api.crc.testing:6443"
CERT_PATH="$HOME/.kube/keycloak-ca.crt"

# Terminal Colors
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0;m' # No Color

echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}   OpenShift Cluster & Keycloak OIDC Setup Assistant${NC}"
echo -e "${CYAN}====================================================${NC}"

# 1. Verify Prerequisites
if ! command -v oc &> /dev/null; then
    echo -e "${RED}❌ Error: 'oc' CLI tool is not installed or not in PATH.${NC}"
    exit 1
fi

# 2. Verify current user is kubeadmin
CURRENT_USER=$(oc whoami 2>/dev/null || echo "not-logged-in")
if [ "$CURRENT_USER" != "kubeadmin" ]; then
    echo -e "${RED}❌ Error: You must be logged into 'oc' as 'kubeadmin' to run this setup.${NC}"
    echo -e "Please log in using: oc login -u kubeadmin -p <password> $API_URL"
    exit 1
fi
echo -e "${GREEN}✅ Confirmed logged in as OpenShift Administrator: $CURRENT_USER${NC}"
echo ""

# 3. Print Manual Keycloak Configuration Steps
echo -e "${YELLOW}📋 STEP-BY-STEP KEYCLOAK UI CONFIGURATION INTERFACE${NC}"
echo -e "Please log into Keycloak (${CYAN}https://${KEYCLOAK_HOST}${NC}) and follow these steps:"
echo "--------------------------------------------------------------------------------"
echo -e "${GREEN}1. Create the Realm:${NC}"
echo "   - Click the 'master' dropdown (top-left) -> 'Create new Realm'."
echo "   - Realm name: openshift"
echo "   - Click 'Create'."
echo ""
echo -e "${GREEN}2. Create the Custom 'groups' Scope:${NC}"
echo "   - Go to 'Client Scopes' (left sidebar) -> 'Create client scope'."
echo "   - Name: groups | Type: Default | Include in Token Scope: On -> Click 'Save'."
echo "   - Click 'Mappers' tab (at the top) -> 'Configure a new mapper' -> 'Group Membership'."
echo "   - Name: groups | Token Claim Name: groups | Full group path: Off -> Click 'Save'."
echo ""
echo -e "${GREEN}3. Create the Clients:${033}"
echo -e "   ${CYAN}A. Web Console Client ('openshift-console')${NC}"
echo "      - Go to 'Clients' -> 'Create client'."
echo "      - Client ID: openshift-console -> Click 'Next'."
echo "      - Toggle 'Client Authentication' to ON (Confidential client) -> Click 'Next'."
echo "      - Valid Redirect URIs: https://console-openshift-console.apps-crc.testing/auth/callback"
echo "      - Click 'Save'."
echo "      - Go to 'Client Scopes' tab (top) -> 'Add client scope' -> Check 'groups' -> Add as 'Default'."
echo "      - Go to 'Credentials' tab (top) and COPY the 'Client Secret'."
echo ""
echo -e "   ${CYAN}B. Command Line Client ('openshift-cli')${NC}"
echo "      - Go to 'Clients' -> 'Create client'."
echo "      - Client ID: openshift-cli -> Leave Client Authentication OFF (Public client) -> Click 'Next'."
echo "      - Valid Redirect URIs: http://localhost -> Click 'Save'."
echo "      - On 'Settings' tab, scroll down to 'Capability config' -> Check 'Direct access grants' -> Click 'Save'."
echo "      - Go to 'Client Scopes' tab (top) -> 'Add client scope' -> Check 'groups' -> Add as 'Default'."
echo ""
echo -e "${GREEN}4. Create Admin Group & User:${NC}"
echo "   - Go to 'Groups' -> 'Create Group' -> Name: openshift_admins -> Click 'Create'."
echo "   - Go to 'Users' -> 'Create a new user' -> Username: openshift_admin."
echo "   - Click 'Join Groups' -> Select 'openshift_admins' -> Click 'Join' -> Click 'Create user'."
echo "   - Go to 'Credentials' tab (top) -> 'Set password' -> Turn 'Temporary' to OFF -> Click 'Save password'."
echo "--------------------------------------------------------------------------------"
echo ""
echo -e "${YELLOW}⏸️  PAUSE: Please complete the steps above in Keycloak before continuing.${NC}"
read -p "Press [ENTER] once you have completed the UI setup and copied the console client secret..."
echo ""

# 4. Prompt securely for the Keycloak Client Secret
echo -e -n "${YELLOW}🔑 Paste your Keycloak 'openshift-console' Client Secret here: ${NC}"
read -s CONSOLE_SECRET
echo "" 

if [ -z "$CONSOLE_SECRET" ]; then
    echo -e "${RED}❌ Error: Client secret cannot be empty.${NC}"
    exit 1
fi

# 5. Extract Keycloak Certificate Globally
echo "🌐 Extracting TLS Certificate from Keycloak..."
mkdir -p "$HOME/.kube"
openssl s_client -connect ${KEYCLOAK_HOST}:443 -showcerts </dev/null 2>/dev/null \
    | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > "$CERT_PATH"

if [ ! -s "$CERT_PATH" ]; then
    echo -e "${RED}❌ Error: Failed to extract CA certificate data from Keycloak.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Saved certificate globally to: $CERT_PATH${NC}"

# 6. Create ConfigMap in OpenShift
echo "📦 Updating cluster ConfigMap with Keycloak CA..."
oc delete configmap external-auth-ca -n openshift-config --ignore-not-found=true
oc create configmap external-auth-ca --from-file=ca-bundle.crt="$CERT_PATH" -n openshift-config

# 7. Create Console Secret in OpenShift
echo "🔒 Updating cluster Secret with Console Client Credentials..."
oc delete secret external-auth-console-secret -n openshift-config --ignore-not-found=true
oc create secret generic external-auth-console-secret --from-literal=clientSecret="$CONSOLE_SECRET" -n openshift-config

# 8. Create ClusterRoleBinding for Admin Rights
echo "🤝 Applying Group RBAC Policies (openshift_admins -> cluster-admin)..."
oc apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: openshift-admins
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: openshift_admins
EOF

# 9. Define and Patch the Authentication Engine
echo "⚙️ Patching Cluster Authentication Resource..."
AUTH_PATCH=$(cat << EOF
spec:
  oidcProviders:
    - claimMappings:
        groups:
          claim: groups
          prefix: ''
        username:
          claim: preferred_username
          prefixPolicy: NoPrefix
      issuer:
        audiences:
          - openshift-console
          - openshift-cli
        issuerCertificateAuthority:
          name: external-auth-ca
        issuerURL: ${KEYCLOAK_URL}
      name: 'rhbk-external-auth'
      oidcClients:
        - clientID: openshift-cli
          componentName: cli
          componentNamespace: openshift-console
        - clientID: openshift-console
          clientSecret:
            name: external-auth-console-secret
          componentName: console
          componentNamespace: openshift-console
  type: OIDC
  webhookTokenAuthenticator: null
EOF
)

oc patch authentication cluster --type="merge" -p "$AUTH_PATCH"

# 10. Clean up local terminal cache to prevent context traps
echo "🧹 Wiping local terminal OIDC token caches..."
oc logout &> /dev/null || true
rm -rf ~/.kube/cache/*

echo -e "${GREEN}====================================================${NC}"
echo -e "${GREEN} 🎉 Automated Configuration Applied Successfully!${NC}"
echo -e "${GREEN}====================================================${NC}"
echo "The core API server and web interfaces are now restarting to mount the configurations."
echo "Run this command to safely watch the cluster update process:"
echo -e "  ${CYAN}watch \"oc get co kube-apiserver console\"${NC}"
echo ""
echo "Once both operators display AVAILABLE=True and PROGRESSING=False, log in from any directory with:"
echo -e "  ${CYAN}oc login --client-id=openshift-cli --exec-plugin=oc-oidc --issuer-url=${KEYCLOAK_URL} --oidc-certificate-authority=$CERT_PATH $API_URL${NC}"
echo -e "${GREEN}====================================================${NC}"
