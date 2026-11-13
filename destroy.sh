#!/bin/bash
# Removes everything Terraform created for this project (VMs, vApp network link, vApp).
# Usage: ./destroy.sh        (asks for confirmation)
#        ./destroy.sh -y     (no confirmation)
set -euo pipefail
cd "$(dirname "$0")"

AUTO=""
[ "${1:-}" = "-y" ] && AUTO="-auto-approve"

terraform destroy $AUTO
