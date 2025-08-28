#!/usr/bin/env bash
# delete-all-pvs-and-pvcs.sh
# Deletes all PVCs from all namespaces, then deletes all PVs.

set -euo pipefail

# --- PVC DELETION ---
echo "Fetching all PVCs from all namespaces..."
# The output format will be "namespace/name"
PVC_LIST=$(kubectl get pvc --all-namespaces -o jsonpath='{range .items[*]}{.metadata.namespace}{"/"}{.metadata.name}{"\n"}{end}')

if [ -z "$PVC_LIST" ]; then
  echo "✅ No PersistentVolumeClaims found."
else
  echo "Found the following PVCs:"
  echo "$PVC_LIST"
  echo

  read -rp "Proceed to delete all these PVCs? (y/N): " CONFIRM_PVC
  if [[ "${CONFIRM_PVC,,}" == "y" ]]; then
    echo
    # Use a while loop to correctly handle lines from the command output
    echo "$PVC_LIST" | while IFS= read -r pvc_with_ns; do
      if [ -z "$pvc_with_ns" ]; then continue; fi
      
      # Split namespace and name
      NAMESPACE=$(echo "$pvc_with_ns" | cut -d'/' -f1)
      PVC_NAME=$(echo "$pvc_with_ns" | cut -d'/' -f2)

      echo "Processing PVC: $PVC_NAME in namespace: $NAMESPACE"

      # Attempt to remove finalizers first, as this is a common cause for being stuck
      echo " → Patching PVC to remove finalizers..."
      kubectl patch pvc "$PVC_NAME" -n "$NAMESPACE" -p '{"metadata":{"finalizers":null}}' --type=merge || {
        echo "    Warning: patch command failed. PVC might already be gone."
      }

      # Now delete the PVC
      echo " → Deleting PVC (force, no grace period)..."
      kubectl delete pvc "$PVC_NAME" -n "$NAMESPACE" --grace-period=0 --force --ignore-not-found=true

      echo " → Done cleaning up $pvc_with_ns."
      echo
    done
    echo "✅ All PVCs processed."
  else
    echo "Aborting PVC deletion."
  fi
fi

echo
echo "--------------------------------------------------"
echo

# --- PV DELETION ---
echo "Fetching all PV names..."
PV_LIST=$(kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')

if [ -z "$PV_LIST" ]; then
  echo "✅ No PersistentVolumes found."
  exit 0
fi

echo "Found the following PVs:"
echo "$PV_LIST"
echo

read -rp "Proceed to delete all these PVs? (y/N): " CONFIRM_PV
if [[ "${CONFIRM_PV,,}" != "y" ]]; then
  echo "Aborting PV deletion."
  exit 1
fi

echo
# Use a while loop for robustness
echo "$PV_LIST" | while IFS= read -r pv; do
  if [ -z "$pv" ]; then continue; fi

  echo "Processing PV: $pv"
  
  # Remove the finalizer first
  echo " → Patching PV to remove finalizers..."
  kubectl patch pv "$pv" -p '{"metadata":{"finalizers":null}}' --type=merge || {
    echo "    Warning: patch command failed. PV might already be gone."
  }

  # Then delete the PV
  echo " → Deleting PV (force, no grace period)..."
  kubectl delete pv "$pv" --grace-period=0 --force --ignore-not-found=true

  echo " → Done cleaning up $pv."
  echo
done

echo "✅ All PVs processed."