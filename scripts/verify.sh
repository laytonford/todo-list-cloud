#!/bin/bash

set -e

REGION="us-east-1"
STACK_NAME="todo-list-cloud"

echo "Checking cloud deployment..."
echo

if ! aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --region "$REGION" > /dev/null 2>&1; then
    echo "FAIL: CloudFormation stack is not deployed"
    exit 1
fi

echo "PASS: cloud deployment is available"

echo
echo "Checking application data through the cloud..."

API_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query "Stacks[0].Outputs[?OutputKey=='ApiUrl'].OutputValue" \
    --output text \
    --region "$REGION")

if [ ! -f "frontend/config.js" ]; then
    echo "FAIL: frontend/config.js does not exist"
    echo "Run ./scripts/deploy.sh first"
    exit 1
fi

API_TOKEN=$(python -c "
import re
with open('frontend/config.js') as f:
    content = f.read()
match = re.search(r'token: \"([^\"]+)\"', content)
if not match:
    raise SystemExit(1)
print(match.group(1))
")

if [ -z "$API_TOKEN" ]; then
    echo "FAIL: API token could not be found"
    exit 1
fi

echo
echo "API URL:"
echo "$API_URL"
echo

echo "Creating test task..."

CREATE_RESPONSE=$(curl -s -X POST "$API_URL" \
    -H "Content-Type: application/json" \
    -H "x-api-token: $API_TOKEN" \
    -d '{"description":"verification test"}')

TASK_ID=$(echo "$CREATE_RESPONSE" | python -c "import sys,json; print(json.load(sys.stdin)['id'])")

if [ -z "$TASK_ID" ]; then
    echo "FAIL: task could not be created"
    exit 1
fi

echo "PASS: task was created"

echo
echo "Reading task..."

GET_RESPONSE=$(curl -s -X GET "$API_URL" \
    -H "x-api-token: $API_TOKEN")

if ! echo "$GET_RESPONSE" | python -c "import sys,json; tasks=json.load(sys.stdin); assert any(t['id']==sys.argv[1] for t in tasks)" "$TASK_ID"; then
    echo "FAIL: created task could not be read"
    exit 1
fi

echo "PASS: task was read from cloud storage"

echo
echo "Completing task..."

UPDATE_RESPONSE=$(curl -s -X PUT "$API_URL" \
    -H "Content-Type: application/json" \
    -H "x-api-token: $API_TOKEN" \
    -d "{\"id\":\"$TASK_ID\",\"completed\":true}")

if ! echo "$UPDATE_RESPONSE" | python -c "import sys,json; data=json.load(sys.stdin); assert data.get('message')=='Task updated'"; then
    echo "FAIL: task could not be completed"
    exit 1
fi

echo "PASS: task was completed"

echo
echo "Checking updated task..."

GET_RESPONSE=$(curl -s -X GET "$API_URL" \
    -H "x-api-token: $API_TOKEN")

if ! echo "$GET_RESPONSE" | python -c "import sys,json; tasks=json.load(sys.stdin); assert any(t['id']==sys.argv[1] and t['completed'] is True for t in tasks)" "$TASK_ID"; then
    echo "FAIL: completed task was not stored"
    exit 1
fi

echo "PASS: completed task was stored in cloud storage"

echo
echo "Deleting task..."

DELETE_RESPONSE=$(curl -s -X DELETE "$API_URL" \
    -H "Content-Type: application/json" \
    -H "x-api-token: $API_TOKEN" \
    -d "{\"id\":\"$TASK_ID\"}")

if ! echo "$DELETE_RESPONSE" | python -c "import sys,json; data=json.load(sys.stdin); assert data.get('message')=='Task deleted'"; then
    echo "FAIL: task could not be deleted"
    exit 1
fi

echo "PASS: task was deleted"

echo
echo "PASS: cloud application workflow completed successfully"