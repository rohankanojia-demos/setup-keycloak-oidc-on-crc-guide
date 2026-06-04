#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="keycloak"

echo "========================================="
echo "Removing Keycloak from CRC/OpenShift"
echo "========================================="

echo
echo "[1/5] Removing OpenShift OAuth IDP..."

oc patch oauth cluster --type=json \
  -p='[
    {
      "op":"remove",
      "path":"/spec/identityProviders"
    }
  ]' || true

echo
echo "[2/5] Removing OAuth secret..."

oc delete secret keycloak-secret \
  -n openshift-config \
  --ignore-not-found

echo
echo "[3/5] Removing CA configmap..."

oc delete configmap keycloak-ca \
  -n openshift-config \
  --ignore-not-found

echo
echo "[4/5] Removing Keycloak project..."

oc delete project ${NAMESPACE} \
  --ignore-not-found

echo
echo "[5/5] Removing local certificate..."

rm -f keycloak.crt

echo
echo "========================================="
echo "Cleanup complete"
echo "========================================="
echo
echo "Verify:"
echo "oc get co authentication"
echo "oc get projects"
