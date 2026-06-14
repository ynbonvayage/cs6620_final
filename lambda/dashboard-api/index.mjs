import { DynamoDBClient, ScanCommand, QueryCommand, GetItemCommand } from "@aws-sdk/client-dynamodb";
import { unmarshall } from "@aws-sdk/util-dynamodb";
import { S3Client, GetObjectCommand } from "@aws-sdk/client-s3";
import { SNSClient, SubscribeCommand } from "@aws-sdk/client-sns";

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const sns = new SNSClient({});

const { DYNAMODB_TABLE, S3_BUCKET, VULN_TOPIC_ARN } = process.env;

const CORS_HEADERS = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export const handler = async (event) => {
  const routeKey = event.routeKey ?? "";
  const method = event.requestContext?.http?.method ?? "GET";

  // Handle CORS preflight
  if (method === "OPTIONS") {
    return { statusCode: 200, headers: CORS_HEADERS, body: "" };
  }

  try {
    // GET /api/scans?repo=xxx — list scans, optionally filtered by repo
    if (routeKey === "GET /api/scans") {
      return await listScans(event);
    }

    // GET /api/scans/{scanId} — get a single scan record
    if (routeKey === "GET /api/scans/{scanId}") {
      return await getScan(event);
    }

    // GET /api/reports/{scanId} — fetch full report from S3
    if (routeKey === "GET /api/reports/{scanId}") {
      return await getReport(event);
    }

    // POST /api/subscribe — subscribe email with filter policy
    if (routeKey === "POST /api/subscribe") {
      return await subscribeEmail(event);
    }

    return respond(404, { error: "Not found", routeKey });
  } catch (err) {
    console.error("Dashboard API error:", err);
    return respond(500, { error: "Internal server error", detail: err.message });
  }
};

/**
 * List scans from DynamoDB.
 * Requires ?repo=xxx to query scans for a specific repository via GSI index.
 */
async function listScans(event) {
  const repo = event.queryStringParameters?.repo;

  if (!repo) {
    return respond(400, { error: "Missing required query parameter: repo" });
  }

  // Use the GSI: repo-created_at-index for efficient querying by repo
  const result = await dynamo.send(new QueryCommand({
    TableName: DYNAMODB_TABLE,
    IndexName: "repo-created_at-index",
    KeyConditionExpression: "repo = :repo",
    ExpressionAttributeValues: { ":repo": { S: repo } },
    ScanIndexForward: false, // newest first
    Limit: 100,
  }));
  const items = (result.Items ?? []).map(unmarshall);

  return respond(200, { scans: items, count: items.length });
}

/**
 * Get a single scan record by scan_id (partition key).
 */
async function getScan(event) {
  const scanId = event.pathParameters?.scanId;
  if (!scanId) return respond(400, { error: "Missing scanId" });

  const result = await dynamo.send(new GetItemCommand({
    TableName: DYNAMODB_TABLE,
    Key: { scan_id: { S: scanId } },
  }));

  if (!result.Item) {
    return respond(404, { error: "Scan not found" });
  }

  return respond(200, { scan: unmarshall(result.Item) });
}

/**
 * Fetch the full JSON report from S3.
 * The report is stored at reports/{repo}/{scanId}.json.
 * We first look up the repo from DynamoDB, then fetch from S3.
 */
async function getReport(event) {
  const scanId = event.pathParameters?.scanId;
  if (!scanId) return respond(400, { error: "Missing scanId" });

  // Look up the scan to get the repo name (needed for the S3 key)
  const scanResult = await dynamo.send(new GetItemCommand({
    TableName: DYNAMODB_TABLE,
    Key: { scan_id: { S: scanId } },
  }));

  if (!scanResult.Item) {
    return respond(404, { error: "Scan not found" });
  }

  const scan = unmarshall(scanResult.Item);
  const s3Key = `reports/${scan.repo}/${scanId}.json`;

  try {
    const s3Result = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: s3Key,
    }));

    const bodyStr = await s3Result.Body.transformToString();
    const report = JSON.parse(bodyStr);

    return respond(200, { report });
  } catch (err) {
    if (err.name === "NoSuchKey") {
      return respond(404, { error: "Report not found in S3", key: s3Key });
    }
    throw err;
  }
}

function respond(statusCode, payload) {
  return {
    statusCode,
    headers: CORS_HEADERS,
    body: JSON.stringify(payload),
  };
}

/**
 * Initiates an SNS subscription for the given email with a filter policy
 * on the GitHub username.
 */
async function subscribeEmail(event) {
  if (!VULN_TOPIC_ARN) {
    return respond(500, { error: "Vulnerability topic ARN not configured in environment" });
  }

  let body;
  try {
    body = typeof event.body === "string" ? JSON.parse(event.body) : (event.body ?? {});
  } catch (e) {
    return respond(400, { error: "Invalid JSON body" });
  }

  const { email, githubUsername } = body;
  if (!email || !githubUsername) {
    return respond(400, { error: "Missing email or githubUsername" });
  }

  try {
    const filterPolicy = {
      pr_author: [githubUsername.trim()]
    };

    const subscribeParams = {
      TopicArn: VULN_TOPIC_ARN,
      Protocol: "email",
      Endpoint: email.trim(),
      Attributes: {
        FilterPolicy: JSON.stringify(filterPolicy)
      }
    };

    await sns.send(new SubscribeCommand(subscribeParams));

    return respond(200, { success: true, message: "Subscription initiated. Verification email sent." });
  } catch (err) {
    console.error("SNS subscribe failed:", err);
    return respond(500, { error: "Failed to initiate subscription", detail: err.message });
  }
}
