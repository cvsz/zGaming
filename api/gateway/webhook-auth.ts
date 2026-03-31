import { createHmac, timingSafeEqual } from "node:crypto";

export interface WebhookValidationInput {
  payload: string;
  timestamp: string;
  signature: string;
  secret: string;
  eventId: string;
  maxAgeMs?: number;
  nowMs?: number;
}

export function signWebhookPayload(payload: string, timestamp: string, secret: string): string {
  return createHmac("sha256", secret).update(`${timestamp}.${payload}`).digest("hex");
}

export function verifyWebhookSignature(input: WebhookValidationInput): boolean {
  const nowMs = input.nowMs ?? Date.now();
  const maxAgeMs = input.maxAgeMs ?? 5 * 60 * 1000;
  const timestampMs = Number(input.timestamp);
  if (!Number.isFinite(timestampMs)) {
    return false;
  }

  if (Math.abs(nowMs - timestampMs) > maxAgeMs) {
    return false;
  }
  if (!/^[A-Za-z0-9:_-]{8,128}$/.test(input.eventId)) {
    return false;
  }

  const expected = signWebhookPayload(input.payload, input.timestamp, input.secret);
  const expectedBytes = Buffer.from(expected, "hex");
  const providedBytes = Buffer.from(input.signature, "hex");
  if (expectedBytes.length !== providedBytes.length) {
    return false;
  }

  return timingSafeEqual(expectedBytes, providedBytes);
}
