import { DynamoDBClient, PutItemCommand } from "@aws-sdk/client-dynamodb";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";
import { randomUUID } from "crypto";

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const sns = new SNSClient({});

const { SAST_URL, DYNAMODB_TABLE, S3_BUCKET, VULN_TOPIC_ARN, FAILURE_TOPIC_ARN, DASHBOARD_URL } = process.env;

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

    // Notify failure-alerts SNS topic when scanner is unreachable
    await publishFailureAlert(
      `SAST scanner unreachable for repo "${repo}"`,
      `Scan failed — SAST scanner is unreachable.\n\n` +
      `Repo: ${repo}\n` +
      `Filename: ${filename}\n` +
      `Error: ${err.message}\n` +
      `Time: ${new Date().toISOString()}`
    );

    return respond(502, { error: "SAST scanner unreachable", detail: err.message });
  }

  const summary = scanResult.summary ?? { totalVulnerabilities: 0, high: 0, medium: 0, low: 0 };
  const scanId = randomUUID();
  const createdAt = new Date().toISOString();

  // Persist metadata + full report; notify failure-alerts on any write error.
  try {
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
  } catch (err) {
    console.error("Persistence failed:", err.message);

    // Notify failure-alerts SNS topic when DynamoDB/S3 write fails
    await publishFailureAlert(
      `SecureGate persistence error for repo "${repo}"`,
      `Scan completed but failed to persist results.\n\n` +
      `Repo: ${repo}\n` +
      `Scan ID: ${scanId}\n` +
      `Filename: ${filename}\n` +
      `Error: ${err.message}\n` +
      `Time: ${createdAt}`
    );

    return respond(500, { error: "Failed to persist scan results", detail: err.message });
  }

  // Notify vuln-alerts SNS topic when HIGH severity vulnerabilities are found
  if (summary.high > 0 && VULN_TOPIC_ARN) {
    try {
      const dashboardLink = DASHBOARD_URL ? `\n\nView Scan History on Dashboard: ${DASHBOARD_URL}/?repo=${encodeURIComponent(repo)}` : "";
      await sns.send(new PublishCommand({
        TopicArn: VULN_TOPIC_ARN,
        Subject: `[SecureGate] HIGH vulnerability detected in ${repo}`,
        Message:
          `HIGH severity vulnerabilities detected!\n\n` +
          `Repo: ${repo}\n` +
          `Scan ID: ${scanId}\n` +
          `Filename: ${filename}\n` +
          `Created At: ${createdAt}\n\n` +
          `--- Severity Summary ---\n` +
          `HIGH:   ${summary.high}\n` +
          `MEDIUM: ${summary.medium}\n` +
          `LOW:    ${summary.low}\n` +
          `TOTAL:  ${summary.totalVulnerabilities}\n\n` +
          `View full report in S3: s3://${S3_BUCKET}/reports/${repo}/${scanId}.json` +
          dashboardLink,
      }));
      console.log("Vulnerability alert sent to SNS");
    } catch (snsErr) {
      // SNS publish failure should not block the scan response
      console.error("Failed to publish vulnerability alert:", snsErr.message);
    }
  }

  // GitHub Actions parses response.summary.high to decide pass/fail.
  return respond(200, { scanId, createdAt, summary, dashboardUrl: DASHBOARD_URL });
};

/**
 * Publish a failure alert to the failure-alerts SNS topic.
 * Swallows errors so a notification failure never masks the original error.
 */
async function publishFailureAlert(subject, message) {
  if (!FAILURE_TOPIC_ARN) return;
  try {
    await sns.send(new PublishCommand({
      TopicArn: FAILURE_TOPIC_ARN,
      Subject: subject.substring(0, 100), // SNS subject max 100 chars
      Message: message,
    }));
    console.log("Failure alert sent to SNS");
  } catch (snsErr) {
    console.error("Failed to publish failure alert:", snsErr.message);
  }
}

const respond = (statusCode, payload) => ({
  statusCode,
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(payload),
});
