#!/bin/bash

set -e

REGION="us-east-1"
STACK_NAME="todo-list-cloud"

echo "Removing todo-list cloud deployment..."
echo

if ! aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" > /dev/null 2>&1; then
    echo "FAIL: CloudFormation stack does not exist"
    exit 1
fi

echo "Finding buckets..."

WEBSITE_BUCKET=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --logical-resource-id WebsiteBucket \
    --query "StackResources[0].PhysicalResourceId" \
    --output text \
    --region "$REGION")

DATA_BUCKET=$(aws cloudformation describe-stack-resources \
    --stack-name "$STACK_NAME" \
    --logical-resource-id DataBucket \
    --query "StackResources[0].PhysicalResourceId" \
    --output text \
    --region "$REGION")

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

ARTIFACT_BUCKET="todo-list-artifacts-${ACCOUNT_ID}"

echo "Website bucket: $WEBSITE_BUCKET"
echo "Data bucket: $DATA_BUCKET"
echo "Artifact bucket: $ARTIFACT_BUCKET"
echo

echo "Emptying website bucket..."
aws s3 rm "s3://$WEBSITE_BUCKET" \
    --recursive \
    --region "$REGION"

echo "Emptying data bucket..."
aws s3 rm "s3://$DATA_BUCKET" \
    --recursive \
    --region "$REGION"

echo "Deleting CloudFormation stack..."
aws cloudformation delete-stack \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

echo
echo "Waiting for CloudFormation stack deletion..."

aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION"

echo
echo "Deleting artifact bucket..."
aws s3 rb "s3://$ARTIFACT_BUCKET" \
    --force \
    --region "$REGION"

echo
echo "Removing local deployment configuration..."
rm -f frontend/config.js

echo
echo "Cloud deployment completely removed."