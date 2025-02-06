#!/bin/bash
set -euo pipefail

#-----------------------------------------------------------
# Configuration: Set these via environment variables if desired.
#-----------------------------------------------------------
# The Azure region to check (default: eastus)
region="${AZURE_REGION:-eastus}"

# Optional: Set your resource group (if relevant)
rg="${AZURE_RG:-}"

#-----------------------------------------------------------
# Pre-flight checks
#-----------------------------------------------------------
# Check that Azure CLI is installed.
if ! command -v az &> /dev/null; then
  echo "Azure CLI (az) is not installed. Please install it first."
  exit 1
fi

# Check that jq is installed.
if ! command -v jq &> /dev/null; then
  echo "jq is required. Please install jq."
  exit 1
fi

# Ensure you are logged in.
if ! az account show &> /dev/null; then
  echo "You are not logged in. Run 'az login' to log in."
  exit 1
fi

# Get current subscription info.
subscription=$(az account show --query "id" -o tsv)
echo "Using subscription: $subscription"
if [ -n "$rg" ]; then
  echo "Using resource group: $rg"
fi
echo "Using region: $region"
echo "--------------------------------------"
echo ""

#-----------------------------------------------------------
# 1. Check GPU quota/usage in the region.
#-----------------------------------------------------------
echo "Fetching VM usage/quota info for region $region..."
usage_json=$(az vm list-usage --location "$region" -o json)

# Try to pick out any usage item whose name includes "gpu" (case-insensitive).
gpu_usage=$(echo "$usage_json" | jq '[.[] | select(.name.value | test("gpu"; "i"))]')
if [ "$(echo "$gpu_usage" | jq 'length')" -eq 0 ]; then
  echo "No GPU-specific quota information was found in the usage details."
  echo "Note: Your subscription may not track GPUs separately in the usage metrics."
else
  echo "GPU quota details:"
  # Print a summary: localized name, current usage, limit, and available (limit - current)
  echo "$gpu_usage" | jq 'map({
      quota: .name.localizedValue,
      current: .currentValue,
      limit: .limit,
      available: (.limit - .currentValue)
    })'
fi
echo ""
  
#-----------------------------------------------------------
# 2. List GPU-enabled VM SKUs available in the region.
#-----------------------------------------------------------
echo "Fetching GPU-enabled VM SKUs available in region $region..."
# Get all SKUs for the region.
skus_json=$(az vm list-skus --location "$region" -o json)

# Filter the SKUs for those that have a capability called "GPUs" with a numeric value > 0.
gpu_skus=$(echo "$skus_json" | jq '[.[] |
    select(.capabilities[]? | select(.name=="GPUs" and (.value|tonumber) > 0)) |
    { name: .name,
      gpu_count: (.capabilities[] | select(.name=="GPUs") | .value),
      # Optionally, include other details such as number of vCPUs:
      vcpus: (.capabilities[]? | select(.name=="vCPUs") | .value)
    }
  ]')

if [ "$(echo "$gpu_skus" | jq 'length')" -eq 0 ]; then
  echo "No GPU-enabled VM SKUs were found in region $region."
else
  echo "GPU-enabled VM SKUs in region $region:"
  echo "$gpu_skus" | jq .
fi

echo ""
echo "Summary:"
if [ "$(echo "$gpu_usage" | jq 'length')" -eq 0 ]; then
  echo "  • GPU quota information is not available via the VM usage API."
else
  echo "  • GPU quota (if tracked) is reported above."
fi
echo "  • Available GPU-enabled VM SKUs are listed above."

