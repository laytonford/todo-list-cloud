import base64
import hmac
import json
import os
import re
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET"]
API_TOKEN = os.environ["API_TOKEN"]
ID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def respond(status, body):
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }


def key_for(task_id):
    return f"todos/{task_id}.json"


def lambda_handler(event, context):
    method = event["requestContext"]["http"]["method"]
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    if not hmac.compare_digest(headers.get("x-api-token", ""), API_TOKEN):
        return respond(401, {"error": "Unauthorised"})

    raw = event.get("body") or ""
    if event.get("isBase64Encoded") and raw:
        raw = base64.b64decode(raw).decode("utf-8")
    try:
        data = json.loads(raw) if raw else {}
    except json.JSONDecodeError:
        return respond(400, {"error": "Invalid JSON"})

    if method == "GET":
        tasks = []
        for page in s3.get_paginator("list_objects_v2").paginate(Bucket=BUCKET, Prefix="todos/"):
            for item in page.get("Contents", []):
                body = s3.get_object(Bucket=BUCKET, Key=item["Key"])["Body"].read()
                tasks.append(json.loads(body))
        tasks.sort(key=lambda t: t["created_at"])
        return respond(200, tasks)

    if method == "POST":
        description = str(data.get("description", "")).strip()
        if not description:
            return respond(400, {"error": "Description is required"})
        task = {
            "id": str(uuid.uuid4()),
            "description": description[:200],
            "completed": False,
            "created_at": now(),
            "completed_at": None,
        }
        s3.put_object(Bucket=BUCKET, Key=key_for(task["id"]),
                      Body=json.dumps(task), ContentType="application/json")
        return respond(201, task)

    if method in ("PUT", "DELETE"):
        task_id = str(data.get("id", ""))
        if not ID_RE.match(task_id):
            return respond(400, {"error": "A valid ID is required"})

        if method == "DELETE":
            s3.delete_object(Bucket=BUCKET, Key=key_for(task_id))
            return respond(200, {"message": "Task deleted"})

        if "completed" not in data:
            return respond(400, {"error": "ID and completed are required"})
        try:
            obj = s3.get_object(Bucket=BUCKET, Key=key_for(task_id))
        except ClientError as err:
            if err.response["Error"]["Code"] == "NoSuchKey":
                return respond(404, {"error": "Task not found"})
            raise
        task = json.loads(obj["Body"].read())
        completed = bool(data["completed"])
        if completed and not task["completed"]:
            task["completed_at"] = now()
        elif not completed:
            task["completed_at"] = None
        task["completed"] = completed
        s3.put_object(Bucket=BUCKET, Key=key_for(task_id),
                      Body=json.dumps(task), ContentType="application/json")
        return respond(200, {"message": "Task updated"})

    return respond(405, {"error": "Method not allowed"})