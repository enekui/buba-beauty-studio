import { PutSuppressedDestinationCommand } from "@aws-sdk/client-sesv2";
import { PutCommand } from "@aws-sdk/lib-dynamodb";
import { ses, ddb, nowEpoch, nowIso, log, normalizeEmail } from "./_shared.mjs";

const SENDS_LOG_TTL_SECONDS = 90 * 24 * 60 * 60; // 90 days
const RAW_EVENT_MAX_BYTES = 4 * 1024;

function truncate(str, maxBytes) {
  if (!str) return "";
  const buf = Buffer.from(str, "utf-8");
  if (buf.length <= maxBytes) return str;
  return buf.slice(0, maxBytes).toString("utf-8") + "...[truncated]";
}

async function suppress(email, reason) {
  try {
    await ses.send(
      new PutSuppressedDestinationCommand({ EmailAddress: email, Reason: reason })
    );
  } catch (err) {
    log("warn", "suppress_failed", { email, reason, err: String(err?.name || err) });
  }
}

async function logSend(entry) {
  try {
    await ddb.send(
      new PutCommand({
        TableName: process.env.SENDS_LOG_TABLE_NAME,
        Item: entry,
      })
    );
  } catch (err) {
    log("warn", "sends_log_put_failed", {
      email: entry.recipientEmail,
      err: String(err?.name || err),
    });
  }
}

export const handler = async (event) => {
  const records = event?.Records || [];
  const ttl = nowEpoch() + SENDS_LOG_TTL_SECONDS;
  const ts = nowIso();

  for (const record of records) {
    let message;
    try {
      message = JSON.parse(record?.Sns?.Message || "{}");
    } catch (err) {
      log("error", "sns_message_parse_failed", { err: String(err?.message || err) });
      continue;
    }

    const eventType = (message.eventType || message.notificationType || "").toLowerCase();
    const mail = message.mail || {};
    const messageId = mail.messageId || record?.Sns?.MessageId || "unknown";
    const rawTruncated = truncate(JSON.stringify(message), RAW_EVENT_MAX_BYTES);

    if (eventType === "bounce") {
      const bounce = message.bounce || {};
      const isPermanent = bounce.bounceType === "Permanent";
      const recipients = (bounce.bouncedRecipients || []).map((r) => normalizeEmail(r.emailAddress));
      for (const email of recipients) {
        if (!email) continue;
        if (isPermanent) await suppress(email, "BOUNCE");
        await logSend({
          recipientEmail: email,
          sk: `${messageId}#${ts}`,
          eventType: "bounce",
          reason: `${bounce.bounceType || "unknown"}/${bounce.bounceSubType || "unknown"}`,
          rawEvent: rawTruncated,
          ttl,
        });
        log("info", "bounce_processed", {
          email,
          permanent: isPermanent,
          bounceType: bounce.bounceType,
          bounceSubType: bounce.bounceSubType,
          messageId,
        });
      }
      continue;
    }

    if (eventType === "complaint") {
      const complaint = message.complaint || {};
      const recipients = (complaint.complainedRecipients || []).map((r) =>
        normalizeEmail(r.emailAddress)
      );
      for (const email of recipients) {
        if (!email) continue;
        await suppress(email, "COMPLAINT");
        await logSend({
          recipientEmail: email,
          sk: `${messageId}#${ts}`,
          eventType: "complaint",
          reason: complaint.complaintFeedbackType || "unknown",
          rawEvent: rawTruncated,
          ttl,
        });
        log("info", "complaint_processed", {
          email,
          feedback: complaint.complaintFeedbackType,
          messageId,
        });
      }
      continue;
    }

    log("info", "event_ignored", { eventType, messageId });
  }

  return { processed: records.length };
};
