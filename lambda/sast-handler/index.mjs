import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { randomUUID } from "crypto";

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});

const { SAST_URL, DYNAMODB_TABLE, S3_BUCKET } = process.env;

export const handler = async (event) => {
  // Lambda Function URL delivers the HTTP body as event.body (string).
  let body;
  try {
    const raw = typeof event.body === "string" ? JSON.parse(event.body) : (event.body ?? event);
    body = raw;
  } catch {
    return respond(400, { error: "Invalid JSON body" });
  }

  const { code, filename = "untitled.js", repo = "unknown" } = body;

  if (!code) {
    return respond(400, { error: "Missing required field: code" });
  }

  // Forward code to the SAST scanner running on EC2 behind the ALB (port 80).
  let scanResult;
  try {
    const res = await fetch(`${SAST_URL}/scan/code`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ code, filename }),
    });
    if (!res.ok) throw new Error(`Scanner returned HTTP ${res.status}`);
    scanResult = await res.json();
  } catch (err) {
    console.error("SAST scanner call failed:", err.message);
    return respond(502, { error: "SAST scanner unreachable", detail: err.message });
  }

  const summary = scanResult.summary ?? { totalVulnerabilities: 0, high: 0, medium: 0, low: 0 };
  const scanId = randomUUID();
  const createdAt = new Date().toISOString();

  // Persist metadata — scan_id is the partition key defined in Member B's table schema.
  await dynamo.send(new PutItemCommand({
    TableName: DYNAMODB_TABLE,
    Item: {
      scan_id:    { S: scanId },
      repo:       { S: repo },
      created_at: { S: createdAt },
      filename:   { S: filename },
      high:       { N: String(summary.high) },
      medium:     { N: String(summary.medium) },
      low:        { N: String(summary.low) },
      total:      { N: String(summary.totalVulnerabilities) },
    },
  }));

  // Persist full report to S3 under reports/<repo>/<scanId>.json
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `reports/${repo}/${scanId}.json`,
    Body: JSON.stringify({
      scanId,
      repo,
      filename,
      createdAt,
      summary,
      vulnerabilities: scanResult.vulnerabilities ?? [],
    }),
    ContentType: "application/json",
  }));

  // GitHub Actions parses response.summary.high to decide pass/fail.
  return respond(200, { scanId, createdAt, summary });
};

const respond = (statusCode, payload) => ({
  statusCode,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(payload),
});
