#!/bin/sh
set -e

#
# Script for creating and configuring a GCP project.
#
# Prerequisites:
# - must have IAM permissions to create GCP projects
# - Google Cloud SDK is installed and on the path
#
# Usage: createproject.sh <project> [account] [env] team]
#
# Author: John Topley (john.topley@ons.gov.uk)
#

if [ -z "$1" ]; then
    exit 1
else
    PROJECT_NAME="$1"
fi

if [ -z "$2" ]; then
    USER_ACCOUNT=`gcloud config get-value account`
else
    USER_ACCOUNT=$2
fi

if [ -z "$3" ]; then
    ENV="sandbox"
else
    ENV=$3
fi

if [ -z "$4" ]; then
    TEAM="catd"
else
    TEAM=$4
fi

BILLING_ACCOUNT_ID=""
SANDBOX_FWMT_GATEWAY_FOLDER_ID=""
LONDON_REGION="europe-west2"
LONDON_ZONE="europe-west2-a"

echo "Creating project '$PROJECT_NAME' in 'Sandbox-catd ' folder..."
gcloud projects create "$PROJECT_NAME" \
  --name="$PROJECT_NAME" \
  --folder=$SANDBOX_FWMT_GATEWAY_FOLDER_ID \
  --labels="terraformcatdcatd=census-ai-terraform,team=$TEAM,env=$ENV" \
  --set-as-default \
  --no-user-output-enabled

echo "Linking '$PROJECT_NAME' to billing account..."
gcloud beta billing projects link "$PROJECT_NAME" --billing-account $BILLING_ACCOUNT_ID --no-user-output-enabled

echo "Enabling Compute Engine API..."
gcloud services enable compute.googleapis.com --no-user-output-enabled

echo "Creating local configuration..."
gcloud config configurations create "$PROJECT_NAME" --no-user-output-enabled

echo "Setting '$PROJECT_NAME' as default project..."
gcloud config set project "$PROJECT_NAME" --no-user-output-enabled

echo "Setting '$USER_ACCOUNT' as account..."
gcloud config set account "$USER_ACCOUNT" --no-user-output-enabled

echo "Setting region..."
gcloud config set compute/region $LONDON_REGION --no-user-output-enabled

echo "Setting zone..."
gcloud config set compute/zone $LONDON_ZONE --no-user-output-enabled

echo "Project successfully created:"
gcloud config configurations describe "$PROJECT_NAME"

echo "To apply Census AI infrastructure: ENV=$1 ./apply.sh"