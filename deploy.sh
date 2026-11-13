#!/bin/bash
# One command to build everything: init -> validate -> apply (which also waits until the site is up).
# Usage: ./deploy.sh        (asks for confirmation before creating anything)
#        ./deploy.sh -y     (no confirmation)
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f terraform.tfvars ]; then
  echo "terraform.tfvars not found."
  echo "Run: cp terraform.tfvars.example terraform.tfvars   then put your real VCD user and password in it."
  exit 1
fi
if grep -q '\*\*\*\*\*' terraform.tfvars; then
  echo "terraform.tfvars still contains the ***** placeholder. Put your real VCD password in it."
  exit 1
fi

AUTO=""
[ "${1:-}" = "-y" ] && AUTO="-auto-approve"

terraform init -input=false
terraform validate
terraform apply $AUTO
terraform output
