#!/bin/bash

set -e

REGION="us-east-1"
STACK_NAME="todo-list-cloud"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ARTIFACT_BUCKET="todo-list-artifacts-${ACCOUNT_ID}"

echo "Using AWS account: $ACCOUNT_ID"
echo "Using region: $REGION"

echo "Generating API token..."
API_TOKEN=$(python -c "import secrets; print(secrets.token_hex(16))")

echo "API token generated."

if ! aws s3api head-bucket --bucket "$ARTIFACT_BUCKET" 2>/dev/null; then
    echo "Creating artifact bucket..."

    aws s3api create-bucket \
        --bucket "$ARTIFACT_BUCKET" \
        --region "$REGION"
fi

echo "Packaging CloudFormation template..."

aws cloudformation package \
    --template-file cloudformation/template.yaml \
    --s3-bucket "$ARTIFACT_BUCKET" \
    --output-template-file packaged.yaml \
    --region "$REGION"

echo "Deploying CloudFormation stack..."

aws cloudformation deploy \
    --template-file packaged.yaml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides ApiToken="$API_TOKEN" \
    --region "$REGION"

echo "Getting deployment outputs..."

API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
    --output text \
    --region "$REGION")

WEBSITE_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='WebsiteURL'].OutputValue" \
    --output text \
    --region "$REGION")

WEBSITE_BUCKET=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --query "StackResources[?LogicalResourceId=='WebsiteBucket'].PhysicalResourceId" \
    --output text \
    --region "$REGION")

echo "Website bucket: $WEBSITE_BUCKET"
echo "API URL: $API_URL"

echo "Generating frontend/config.js..."

cat > frontend/config.js <<EOF
window.TODO_CONFIG = { apiUrl: "$API_URL", token: "$API_TOKEN" };
EOF

echo "Uploading website..."

aws s3 sync frontend/ "s3://$WEBSITE_BUCKET/" \
    --delete \
    --region "$REGION"

echo ""
echo "Deployment complete."
echo "Website: $WEBSITE_URL"
echo "API: $API_URL"