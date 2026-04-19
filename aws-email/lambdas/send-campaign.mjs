import { randomUUID } from "node:crypto";
import {
  ListContactsCommand,
  CreateEmailTemplateCommand,
  UpdateEmailTemplateCommand,
  DeleteEmailTemplateCommand,
  SendBulkEmailCommand,
} from "@aws-sdk/client-sesv2";
import { PutCommand, UpdateCommand } from "@aws-sdk/lib-dynamodb";
import {
  ses,
  ddb,
  isValidEmail,
  normalizeEmail,
  nowIso,
  log,
  jsonResponse,
  parseBody,
} from "./_shared.mjs";

const BULK_CHUNK_SIZE = 50;
const MAX_TEST_RECIPIENTS = 5;

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function listOptedInContacts(listName, topicName) {
  const emails = [];
  let nextToken;
  do {
    const res = await ses.send(
      new ListContactsCommand({
        ContactListName: listName,
        Filter: {
          FilteredStatus: "OPT_IN",
          TopicFilter: { TopicName: topicName, UseDefaultIfPreferenceUnavailable: false },
        },
        PageSize: 100,
        NextToken: nextToken,
      })
    );
    for (const c of res?.Contacts || []) {
      if (c?.EmailAddress && !c?.UnsubscribeAll) emails.push(normalizeEmail(c.EmailAddress));
    }
    nextToken = res?.NextToken;
  } while (nextToken);
  return emails;
}

async function upsertTemplate({ name, subject, html, text }) {
  const TemplateContent = {
    Subject: subject,
    Html: html,
    Text: text || undefined,
  };
  try {
    await ses.send(
      new CreateEmailTemplateCommand({ TemplateName: name, TemplateContent })
    );
  } catch (err) {
    if (err?.name === "AlreadyExistsException") {
      await ses.send(
        new UpdateEmailTemplateCommand({ TemplateName: name, TemplateContent })
      );
    } else {
      throw err;
    }
  }
}

export const handler = async (event) => {
  if (event?.requestContext?.http?.method === "OPTIONS" || event?.httpMethod === "OPTIONS") {
    return jsonResponse(event, 204, {});
  }

  const actor =
    event?.requestContext?.authorizer?.jwt?.claims?.email ||
    event?.requestContext?.authorizer?.claims?.email ||
    "unknown";

  const campaignId = randomUUID();
  const listName = process.env.CONTACT_LIST_NAME;
  const topicName = process.env.TOPIC_NAME || "promociones";
  const templateName = `campaign-${campaignId}`;

  try {
    const body = parseBody(event);
    if (!body || typeof body !== "object") {
      return jsonResponse(event, 400, { error: "JSON inválido." });
    }

    const subject = typeof body.subject === "string" ? body.subject.trim() : "";
    const htmlBody = typeof body.htmlBody === "string" ? body.htmlBody : "";
    const plainBody = typeof body.plainBody === "string" ? body.plainBody : "";
    const topic = typeof body.topic === "string" && body.topic.trim() ? body.topic.trim() : topicName;
    const testRecipients = Array.isArray(body.testRecipients) ? body.testRecipients : [];

    if (!subject || !htmlBody) {
      return jsonResponse(event, 400, { error: "Faltan 'subject' y/o 'htmlBody'." });
    }

    const testMode = testRecipients.length > 0;
    let recipients = [];

    if (testMode) {
      recipients = testRecipients
        .slice(0, MAX_TEST_RECIPIENTS)
        .map(normalizeEmail)
        .filter(isValidEmail);
      if (recipients.length === 0) {
        return jsonResponse(event, 400, { error: "testRecipients no contiene emails válidos." });
      }
    } else {
      recipients = await listOptedInContacts(listName, topic);
    }

    const createdAt = nowIso();
    await ddb.send(
      new PutCommand({
        TableName: process.env.CAMPAIGNS_TABLE_NAME,
        Item: {
          campaignId,
          createdAt,
          subject,
          topic,
          recipientCount: recipients.length,
          status: "sending",
          testMode,
          createdBy: actor,
        },
      })
    );

    log("info", "campaign_start", {
      campaignId,
      actor,
      topic,
      recipientCount: recipients.length,
      testMode,
    });

    if (recipients.length === 0) {
      await ddb.send(
        new UpdateCommand({
          TableName: process.env.CAMPAIGNS_TABLE_NAME,
          Key: { campaignId, createdAt },
          UpdateExpression: "SET #s = :s, completedAt = :c",
          ExpressionAttributeNames: { "#s": "status" },
          ExpressionAttributeValues: { ":s": "completed", ":c": nowIso() },
        })
      );
      return jsonResponse(event, 200, { campaignId, recipientCount: 0, status: "completed" });
    }

    await upsertTemplate({
      name: templateName,
      subject,
      html: htmlBody,
      text: plainBody,
    });

    const fromAddress = `${process.env.SENDER_FROM_NAME} <${process.env.SENDER_FROM_EMAIL}>`;
    const chunks = chunk(recipients, BULK_CHUNK_SIZE);
    let accepted = 0;
    let rejected = 0;

    for (const group of chunks) {
      const BulkEmailEntries = group.map((email) => ({
        Destination: { ToAddresses: [email] },
        ReplacementEmailContent: undefined,
      }));

      try {
        const res = await ses.send(
          new SendBulkEmailCommand({
            FromEmailAddress: fromAddress,
            ReplyToAddresses: process.env.REPLY_TO_EMAIL ? [process.env.REPLY_TO_EMAIL] : undefined,
            ConfigurationSetName: process.env.CONFIGURATION_SET_NAME,
            DefaultContent: {
              Template: {
                TemplateName: templateName,
                TemplateData: "{}",
              },
            },
            BulkEmailEntries,
            ...(testMode
              ? {}
              : {
                  ListManagementOptions: {
                    ContactListName: listName,
                    TopicName: topic,
                  },
                }),
          })
        );
        const results = res?.BulkEmailEntryResults || [];
        for (const r of results) {
          if (r?.Status === "SUCCESS") accepted++;
          else rejected++;
        }
      } catch (err) {
        rejected += group.length;
        log("error", "bulk_chunk_failed", {
          campaignId,
          err: String(err?.name || err),
          size: group.length,
        });
      }
    }

    await ddb.send(
      new UpdateCommand({
        TableName: process.env.CAMPAIGNS_TABLE_NAME,
        Key: { campaignId, createdAt },
        UpdateExpression: "SET #s = :s, completedAt = :c, accepted = :a, rejected = :r",
        ExpressionAttributeNames: { "#s": "status" },
        ExpressionAttributeValues: {
          ":s": "completed",
          ":c": nowIso(),
          ":a": accepted,
          ":r": rejected,
        },
      })
    );

    // Clean up ad-hoc template to avoid template-count bloat. Best effort.
    await ses
      .send(new DeleteEmailTemplateCommand({ TemplateName: templateName }))
      .catch((err) =>
        log("warn", "template_delete_failed", { templateName, err: String(err?.name || err) })
      );

    log("info", "campaign_completed", {
      campaignId,
      actor,
      recipientCount: recipients.length,
      accepted,
      rejected,
    });

    return jsonResponse(event, 200, {
      campaignId,
      recipientCount: recipients.length,
      accepted,
      rejected,
      status: "completed",
    });
  } catch (err) {
    log("error", "campaign_failed", {
      campaignId,
      actor,
      err: String(err?.name || err),
      msg: err?.message,
    });
    try {
      await ddb.send(
        new UpdateCommand({
          TableName: process.env.CAMPAIGNS_TABLE_NAME,
          Key: { campaignId, createdAt: nowIso() },
          UpdateExpression: "SET #s = :s",
          ExpressionAttributeNames: { "#s": "status" },
          ExpressionAttributeValues: { ":s": "failed" },
        })
      );
    } catch {
      // audit update is best-effort
    }
    return jsonResponse(event, 500, { error: "No hemos podido lanzar la campaña." });
  }
};
