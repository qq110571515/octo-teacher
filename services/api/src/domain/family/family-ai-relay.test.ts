import assert from "node:assert/strict";
import test from "node:test";
import { FamilyCloudError } from "./cloud-types.js";
import { parseFamilyAIChatInput, parseFamilyAITranscriptionInput } from "./family-ai-relay.js";

test("family AI relay accepts a bounded text-only child request", () => {
  const parsed = parseFamilyAIChatInput({
    system: "child safety prompt",
    user: "child_message: hello",
    images: [],
    homeworkSensitive: false,
  }, false);
  assert.equal(parsed.user, "child_message: hello");
  assert.equal(parsed.homeworkSensitive, false);
});

test("family AI relay rejects images unless guardian enabled them", () => {
  assert.throws(() => parseFamilyAIChatInput({
    system: "child safety prompt",
    user: "what is this",
    images: [{ mimeType: "image/jpeg", base64Data: "aGVsbG8=" }],
  }, false), FamilyCloudError);
});

test("family AI relay rejects non-image payloads", () => {
  assert.throws(() => parseFamilyAIChatInput({
    system: "child safety prompt",
    user: "what is this",
    images: [{ mimeType: "text/plain", base64Data: "aGVsbG8=" }],
  }, true), FamilyCloudError);
});

test("family AI relay accepts bounded m4a transcription input", () => {
  const parsed = parseFamilyAITranscriptionInput({
    mimeType: "audio/m4a",
    base64Data: "aGVsbG8=",
  });
  assert.equal(parsed.mimeType, "audio/m4a");
});

test("family AI relay rejects unsupported audio types", () => {
  assert.throws(() => parseFamilyAITranscriptionInput({
    mimeType: "application/octet-stream",
    base64Data: "aGVsbG8=",
  }), FamilyCloudError);
});
