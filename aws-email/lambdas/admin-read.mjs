/**
 * admin-read.mjs
 *
 * Handler de rutas de lectura del panel admin.
 *   - GET /admin/campaigns            → lista las últimas campañas.
 *   - GET /admin/audience/count?topic → devuelve {count} de contactos opt-in
 *                                        del topic indicado.
 *
 * Autenticado upstream via Cognito JWT authorizer en API Gateway.
 */

import { SESv2Client, ListContactsCommand } from "@aws-sdk/client-sesv2";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, ScanCommand, QueryCommand } from "@aws-sdk/lib-dynamodb";

const ses = new SESv2Client({});
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

const CONTACT_LIST_NAME = process.env.CONTACT_LIST_NAME;
const CAMPAIGNS_TABLE = process.env.CAMPAIGNS_TABLE_NAME;
const CORS_ORIGINS = (process.env.CORS_ALLOWED_ORIGINS ?? "").split(",").map((s) => s.trim()).filter(Boolean);

function corsHeaders(origin) {
  const allow = origin && CORS_ORIGINS.includes(origin) ? origin : CORS_ORIGINS[0] ?? "*";
  return {
    "access-control-allow-origin": allow,
    "access-control-allow-methods": "GET, OPTIONS",
    "access-control-allow-headers": "Content-Type, Authorization",
    "vary": "Origin",
  };
}

function jsonResponse(statusCode, body, origin) {
  return {
    statusCode,
    headers: { "content-type": "application/json; charset=utf-8", ...corsHeaders(origin) },
    body: JSON.stringify(body),
  };
}

function log(level, msg, extra = {}) {
  console.log(JSON.stringify({ level, msg, ...extra }));
}

async function listCampaigns(limit = 10) {
  const out = await ddb.send(
    new ScanCommand({
      TableName: CAMPAIGNS_TABLE,
      Limit: 100,
    })
  );
  const items = (out.Items ?? [])
    .sort((a, b) => (b.createdAt ?? "").localeCompare(a.createdAt ?? ""))
    .slice(0, limit)
    .map((item) => ({
      campaignId: item.campaignId,
      createdAt: item.createdAt,
      subject: item.subject,
      topic: item.topic,
      recipientCount: item.recipientCount,
      status: item.status,
      testMode: item.testMode ?? false,
    }));
  return items;
}

async function countAudience(topicName) {
  let count = 0;
  let nextToken;
  do {
    const resp = await ses.send(
      new ListContactsCommand({
        ContactListName: CONTACT_LIST_NAME,
        Filter: {
          FilteredStatus: "OPT_IN",
          TopicFilter: topicName
            ? { TopicName: topicName, UseDefaultIfPreferenceUnavailable: false }
            : undefined,
        },
        PageSize: 100,
        NextToken: nextToken,
      })
    );
    count += (resp.Contacts ?? []).length;
    nextToken = resp.NextToken;
  } while (nextToken);
  return count;
}

export const handler = async (event) => {
  const origin = event.headers?.origin ?? event.headers?.Origin;
  const rawPath = event.rawPath ?? event.requestContext?.http?.path ?? "";
  const method = event.requestContext?.http?.method ?? "GET";

  log("info", "admin-read request", { rawPath, method });

  try {
    if (method === "OPTIONS") {
      return { statusCode: 204, headers: corsHeaders(origin) };
    }

    if (rawPath.endsWith("/admin/campaigns") && method === "GET") {
      const limit = parseInt(event.queryStringParameters?.limit ?? "10", 10);
      const items = await listCampaigns(Number.isFinite(limit) ? limit : 10);
      return jsonResponse(200, { items }, origin);
    }

    if (rawPath.endsWith("/admin/audience/count") && method === "GET") {
      const topic = event.queryStringParameters?.topic ?? process.env.TOPIC_NAME;
      const count = await countAudience(topic);
      return jsonResponse(200, { count, topic }, origin);
    }

    return jsonResponse(404, { error: "not_found" }, origin);
  } catch (err) {
    log("error", "admin-read failed", { error: err.message, stack: err.stack });
    return jsonResponse(500, { error: "internal_error" }, origin);
  }
};
