# Keycloak OIDC Setup for OpenShift CRC

This guide walks you through setting up Keycloak as an OpenID Connect (OIDC) identity provider for OpenShift running on CodeReady Containers (CRC).

## Prerequisites

- OpenShift CodeReady Containers (CRC) running
- `oc` CLI tool installed and in PATH
- Access to kubeadmin credentials
- Internet connection to pull Keycloak image

## Overview

The setup process consists of three main phases:

1. **Install Keycloak** using `install-keycloak.sh`
2. **Configure Keycloak manually** through the web UI
3. **Configure OpenShift OIDC** using `setup-keycloack-oidc.sh`

---

## Phase 1: Install Keycloak

### Step 1: Run the Installation Script

```bash
./install-keycloak.sh
```

This script will:
- Create a `keycloak` namespace
- Deploy Keycloak version 26.6.2
- Configure admin credentials (default: admin/admin)
- Create an edge route with TLS
- **Automatically extract the route certificate** to `keycloak.crt`
- Create an OpenShift CA configmap from the certificate

### Step 2: Note the Keycloak URL

At the end of the installation, you'll see:

```
========================================
KEYCLOAK INSTALLED
========================================

URL:
https://keycloak-keycloak.apps-crc.testing

Admin username: admin
Admin password: admin
```

**Save this URL** - you'll need it for the next steps.

---

## Phase 2: Configure Keycloak UI

### Step 1: Login to Keycloak

Open your browser and navigate to the Keycloak URL from Phase 1:

```
https://keycloak-keycloak.apps-crc.testing
```

Login with:
- **Username**: `admin`
- **Password**: `admin`

### Step 2: Create the Realm

1. Click the **master** dropdown in the top-left corner
2. Select **Create new Realm**
3. Enter realm name: `openshift`
4. Click **Create**

### Step 3: Create Custom 'groups' Scope

1. Navigate to **Client Scopes** in the left sidebar
2. Click **Create client scope**
3. Configure:
   - **Name**: `groups`
   - **Type**: `Default`
   - **Include in Token Scope**: `On`
4. Click **Save**
5. Click the **Mappers** tab at the top
6. Click **Configure a new mapper** → **Group Membership**
7. Configure:
   - **Name**: `groups`
   - **Token Claim Name**: `groups`
   - **Full group path**: `Off`
8. Click **Save**

### Step 4: Create Web Console Client

1. Navigate to **Clients** in the left sidebar
2. Click **Create client**
3. **Step 1 - General Settings**:
   - **Client ID**: `openshift-console`
   - Click **Next**
4. **Step 2 - Capability config**:
   - Toggle **Client Authentication** to `ON` (Confidential client)
   - Click **Next**
5. **Step 3 - Login settings**:
   - **Valid Redirect URIs**: `https://console-openshift-console.apps-crc.testing/auth/callback`
   - Click **Save**
6. Go to **Client Scopes** tab (at the top)
7. Click **Add client scope**
8. Check `groups` and click **Add** → **Default**
9. Go to **Credentials** tab
10. **IMPORTANT**: Copy the **Client Secret** - you'll need this in Phase 3

### Step 5: Create CLI Client

1. Navigate to **Clients** → **Create client**
2. **Step 1 - General Settings**:
   - **Client ID**: `openshift-cli`
   - Click **Next**
3. **Step 2 - Capability config**:
   - Leave **Client Authentication** `OFF` (Public client)
   - Click **Next**
4. **Step 3 - Login settings**:
   - **Valid Redirect URIs**: `http://localhost`
   - Click **Save**
5. On the **Settings** tab, scroll to **Capability config**
6. Check **Direct access grants**
7. Click **Save**
8. Go to **Client Scopes** tab
9. Click **Add client scope**
10. Check `groups` and click **Add** → **Default**

### Step 6: Create Admin Group

1. Navigate to **Groups** in the left sidebar
2. Click **Create Group**
3. **Name**: `openshift_admins`
4. Click **Create**

### Step 7: Create Admin User

1. Navigate to **Users** in the left sidebar
2. Click **Create new user**
3. **Username**: `openshift_admin`
4. Click **Join Groups**
5. Select `openshift_admins`
6. Click **Join**
7. Click **Create user**
8. Go to **Credentials** tab
9. Click **Set password**
10. Enter a password
11. Toggle **Temporary** to `OFF`
12. Click **Save password**

---

## Phase 3: Configure OpenShift OIDC

### Step 1: Ensure You're Logged in as kubeadmin

```bash
oc login -u kubeadmin -p <your-kubeadmin-password> https://api.crc.testing:6443
```

### Step 2: Run the OIDC Setup Script

```bash
./setup-keycloack-oidc.sh
```

The script will:
- Verify prerequisites
- Display the UI configuration steps (which you've already completed)
- Pause and wait for you to press ENTER

### Step 3: Enter Client Secret

When prompted:
```
🔑 Paste your Keycloak 'openshift-console' Client Secret here:
```

Paste the **Client Secret** you copied in Phase 2, Step 4.9.

### Step 4: Wait for Completion

The script will automatically:
- **Extract the Keycloak TLS certificate** to `~/.kube/keycloak-ca.crt`
- Create ConfigMap with the CA certificate (`external-auth-ca`)
- Create Secret with console client credentials (`external-auth-console-secret`)
- Apply RBAC policies (openshift_admins → cluster-admin)
- Patch the cluster authentication resource
- Clear local OIDC token caches

> **Note**: The certificate extraction happens automatically using `openssl s_client` - you don't need to manually download or create any certificates.

---

## Phase 4: Verify and Login

### Step 1: Monitor Cluster Operators

Watch for the cluster operators to restart and become available:

```bash
watch "oc get co kube-apiserver console"
```

Wait until both show:
- `AVAILABLE=True`
- `PROGRESSING=False`

Press `Ctrl+C` when complete.

### Step 2: Login via OIDC

Login using the new OIDC provider:

```bash
oc login \
  --client-id=openshift-cli \
  --exec-plugin=oc-oidc \
  --issuer-url=https://keycloak-keycloak.apps-crc.testing/realms/openshift \
  --oidc-certificate-authority=$HOME/.kube/keycloak-ca.crt \
  https://api.crc.testing:6443
```

When prompted:
- **Username**: `openshift_admin`
- **Password**: The password you set in Phase 2, Step 7

### Step 3: Verify Access

```bash
oc whoami
```

Should output: `openshift_admin`

```bash
oc auth can-i create project
```

Should output: `yes` (because openshift_admin is in openshift_admins group with cluster-admin role)

### Step 4: Access Web Console

Open your browser to:

```
https://console-openshift-console.apps-crc.testing
```

Click **keycloak** (or **rhbk-external-auth**) and login with the same credentials.

---

## Configuration Details

### Default Values

| Parameter | Value |
|-----------|-------|
| Keycloak Namespace | `keycloak` |
| Keycloak Version | `26.6.2` |
| Admin Username | `admin` |
| Admin Password | `admin` |
| Realm Name | `openshift` |
| Console Client ID | `openshift-console` |
| CLI Client ID | `openshift-cli` |
| Admin Group | `openshift_admins` |
| Admin User | `openshift_admin` |

### OIDC Claim Mappings

- **Username**: `preferred_username` (no prefix)
- **Groups**: `groups` (no prefix)

### RBAC

The `openshift_admins` group is bound to the `cluster-admin` ClusterRole, giving all members full cluster access.

---

## Troubleshooting

### Certificate Issues

If you encounter certificate errors, re-extract the certificate:

```bash
openssl s_client -connect keycloak-keycloak.apps-crc.testing:443 -showcerts </dev/null 2>/dev/null \
  | sed -n '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' > ~/.kube/keycloak-ca.crt
```

### Keycloak Not Accessible

Check the Keycloak pod status:

```bash
oc get pods -n keycloak
oc logs -n keycloak deployment/keycloak
```

### Authentication Operator Issues

Check the authentication operator:

```bash
oc get co authentication
oc describe co authentication
```

### Reset to kubeadmin

If you need to revert to kubeadmin login:

```bash
oc login -u kubeadmin -p <password> https://api.crc.testing:6443
```

---

## Uninstalling

To remove Keycloak:

```bash
./uninstall-keycloak.sh
```

To remove OIDC configuration from OpenShift:

```bash
oc patch authentication cluster --type=json -p '[{"op": "remove", "path": "/spec/oidcProviders"}]'
oc delete secret external-auth-console-secret -n openshift-config
oc delete configmap external-auth-ca -n openshift-config
oc delete clusterrolebinding openshift-admins
```

---

## Notes

- The setup uses Keycloak in development mode (`start-dev`) which is **not suitable for production**
- TLS certificates are self-signed via OpenShift's edge route
- The `oc-oidc` exec plugin is required for CLI authentication
- Browser-based authentication flows require access to both the Keycloak URL and the OpenShift console URL

---

## License

This setup is provided as-is for development and testing purposes.
