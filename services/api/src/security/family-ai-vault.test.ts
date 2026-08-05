import assert from "node:assert/strict";
import test from "node:test";
import { randomBytes } from "node:crypto";
import { decryptFamilyAISecret, encryptFamilyAISecret } from "./family-ai-vault.js";

test("family AI vault encrypts without preserving plaintext and decrypts losslessly", () => {
  const previous = process.env.FAMILY_AI_VAULT_KEY;
  process.env.FAMILY_AI_VAULT_KEY = randomBytes(32).toString("base64");
  try {
    const encrypted = encryptFamilyAISecret("sk-family-test-secret");
    assert.equal(encrypted.includes("sk-family-test-secret"), false);
    assert.equal(decryptFamilyAISecret(encrypted), "sk-family-test-secret");
  } finally {
    if (previous === undefined) delete process.env.FAMILY_AI_VAULT_KEY;
    else process.env.FAMILY_AI_VAULT_KEY = previous;
  }
});

test("family AI vault fails closed when the server secret is missing", () => {
  const previous = process.env.FAMILY_AI_VAULT_KEY;
  delete process.env.FAMILY_AI_VAULT_KEY;
  try {
    assert.throws(() => encryptFamilyAISecret("secret"), /family_ai_vault_not_configured/);
  } finally {
    if (previous !== undefined) process.env.FAMILY_AI_VAULT_KEY = previous;
  }
});
