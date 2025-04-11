#!/bin/bash
# Script to find resources using a particular GPU SKU in a given region

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <region> <gpu-sku>"
    echo "Example: $0 eastus Standard_NC6"
    exit 1
fi

REGION=$1
SKU=$2

echo "Searching for resources in region '$REGION' using GPU SKU '$SKU'..."

#########################
# Check for Virtual Machines (VMs)
#########################
echo -e "\n=== Virtual Machines (VMs) ==="
# Filter VMs by location and by the hardwareProfile.vmSize field
az vm list --query "[?location=='$REGION' && hardwareProfile.vmSize=='$SKU']" -o table

#########################
# Check for Virtual Machine Scale Sets (VMSS)
#########################
echo -e "\n=== Virtual Machine Scale Sets (VMSS) ==="
# Filter VMSS by location and by sku.name field
az vmss list --query "[?location=='$REGION' && sku.name=='$SKU']" -o table

#########################
# Check for AKS clusters that have node pools with the given SKU
#########################
echo -e "\n=== AKS Clusters ==="
# Get all AKS clusters in the specified region as JSON
aks_clusters=$(az aks list --query "[?location=='$REGION']" -o json)

# Use jq to filter clusters where any node pool has a matching vmSize
# and then print out the cluster name, resource group, and the node pool(s) that match.
echo "$aks_clusters" | jq -r --arg sku "$SKU" '
  .[] 
  | select(any(.agentPoolProfiles[]; .vmSize == $sku))
  | "Cluster: \(.name) (Resource Group: \(.resourceGroup))\nNode Pools using '$SKU': " + 
    (.agentPoolProfiles 
     | map(select(.vmSize==$sku) | .name) 
     | join(", "))
  + "\n----------------"'

