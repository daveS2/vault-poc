#bin/bash

# exit if fails
set -e

# expect a project variable
if [ -z "$PROJECT" ]; then
  echo "Missing PROJECT variable"
  exit 1
fi

# variables
GCPPROJECT=$PROJECT
REGION=europe-west2

# Create the bucket, will error if already exists
gsutil mb -p $PROJECT -c regional -l $REGION gs://$PROJECT-tfstate/ || true

# remove local state
rm -rf .terraform

# terraform init with bucket state
terraform init --backend-config bucket=$PROJECT-tfstate