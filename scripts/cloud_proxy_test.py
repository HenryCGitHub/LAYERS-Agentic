#!/usr/bin/env python3
"""Headless test for LAYERS Cloud Functions proxy & auth/invite helpers (`functions/index.js`)."""

from __future__ import annotations

import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

NODE_TEST = r"""
const assert = require("assert");
const fs = require("fs");
const Module = require("module");
const path = require("path");

const repoRoot = path.resolve(process.argv[1]);
const functionsDir = path.join(repoRoot, "functions");

// 1. Removed Godot Cloud files must stay deleted.
for (const legacyFile of [
  "godot_agent_runner.js",
  "godot_link_sync.js",
  "godot_spec_context.js",
  "godot_spec_guard.js",
]) {
  assert(
    !fs.existsSync(path.join(functionsDir, legacyFile)),
    `Legacy Godot module still exists: functions/${legacyFile}`
  );
}

for (const fname of fs.readdirSync(functionsDir)) {
  if (!fname.endsWith(".js")) continue;
  const lineCount = fs
    .readFileSync(path.join(functionsDir, fname), "utf8")
    .split(/\r?\n/).length;
  assert(
    lineCount <= 1100,
    `Expected functions/${fname} <= 1100 lines, got ${lineCount}`
  );
}

// 2. Mock Firebase & Nodemailer dependencies cleanly for offline unit testing.
const aiAccessDocs = new Map([
  ["approved@studio.dev", { email: "approved@studio.dev", status: "approved" }],
  ["invited@studio.dev", { email: "invited@studio.dev", status: "invited" }],
  ["revoked@studio.dev", { email: "revoked@studio.dev", status: "revoked" }],
]);
const deletedUids = [];
const revokedUids = [];
const tokenMap = {
  "tok-admin": { uid: "u-admin", email: "henryyoungchoi@gmail.com", email_verified: true, name: "Owner" },
  "tok-approved": { uid: "u-app", email: "approved@studio.dev", email_verified: true, name: "Approved Dev" },
  "tok-invited": { uid: "u-inv", email: "invited@studio.dev", email_verified: true, name: "Invited Dev" },
  "tok-uninvited": { uid: "u-uninv", email: "stranger@studio.dev", email_verified: true, name: "Stranger" },
  "tok-revoked": { uid: "u-rev", email: "revoked@studio.dev", email_verified: true, name: "Revoked Dev" },
};

const mockFirestore = {
  collection(colName) {
    assert.strictEqual(colName, "ai_access", `Unexpected collection access: ${colName}`);
    return {
      doc(docId) {
        return {
          async get() {
            const data = aiAccessDocs.get(docId);
            return { exists: Boolean(data), data: () => (data ? { ...data } : undefined) };
          },
          async set(payload, opts) {
            const prev = opts && opts.merge && aiAccessDocs.has(docId) ? aiAccessDocs.get(docId) : {};
            aiAccessDocs.set(docId, { ...prev, ...payload });
          },
        };
      },
    };
  },
};

const mockAuth = {
  async verifyIdToken(idToken) {
    if (!tokenMap[idToken]) {
      throw new Error("invalid token");
    }
    return tokenMap[idToken];
  },
  async deleteUser(uid) {
    deletedUids.push(uid);
  },
  async revokeRefreshTokens(uid) {
    revokedUids.push(uid);
  },
  async getUserByEmail(email) {
    const match = Object.values(tokenMap).find((u) => u.email === email);
    if (!match) throw new Error("not found");
    return match;
  },
};

const origLoad = Module._load;
Module._load = function patchedLoad(request, parent, isMain) {
  if (request === "firebase-functions/v2/https") {
    return { onRequest: (_opts, handler) => handler };
  }
  if (request === "firebase-functions/params") {
    return {
      defineSecret: (name) => ({
        value: () => (name === "GEMINI_API_KEY" ? "test-gemini-secret" : ""),
      }),
    };
  }
  if (request === "firebase-admin/app") {
    return { initializeApp: () => ({}) };
  }
  if (request === "firebase-admin/auth") {
    return { getAuth: () => mockAuth };
  }
  if (request === "firebase-admin/firestore") {
    return {
      getFirestore: () => mockFirestore,
      FieldValue: { serverTimestamp: () => "SERVER_TS" },
    };
  }
  if (request === "nodemailer") {
    return {
      createTransport: () => ({ sendMail: async () => ({ messageId: "mock" }) }),
    };
  }
  return origLoad.call(this, request, parent, isMain);
};

let fetchCalls = [];
global.fetch = async (url, opts) => {
  fetchCalls.push({ url, opts });
  return {
    status: 200,
    async text() {
      return JSON.stringify({ candidates: [{ content: { parts: [{ text: "ok" }] } }] });
    },
  };
};

const indexMod = require(path.join(functionsDir, "index.js"));
const handler = indexMod.geminiProxy;
const helpers = indexMod._testHelpers;

assert(helpers.ALLOWED_MODELS.includes("gemini-4-hydrogen"));
assert(helpers.ALLOWED_MODELS.includes("gemini-flash-latest"));
assert.strictEqual(helpers.computeActiveGodotEpicPayload, undefined);
assert.strictEqual(helpers.hashLinkToken, undefined);

async function invoke(method, reqPath, { token = null, body = null, rawBytes = null } = {}) {
  const rawBody =
    rawBytes != null
      ? Buffer.alloc(rawBytes, "a")
      : body != null
        ? Buffer.from(JSON.stringify(body), "utf8")
        : undefined;
  const req = {
    method,
    path: reqPath,
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body,
    rawBody,
  };
  let statusCode = 200;
  let sentBody = null;
  let contentType = "application/json";
  const res = {
    status(code) {
      statusCode = code;
      return res;
    },
    type(t) {
      contentType = t;
      return res;
    },
    json(obj) {
      sentBody = obj;
      return res;
    },
    send(payload) {
      sentBody = typeof payload === "string" ? JSON.parse(payload) : payload;
      return res;
    },
  };
  await handler(req, res);
  return { statusCode, body: sentBody, contentType };
}

(async () => {
  // 3. Removed /godotLink/* routes return 404.
  for (const [m, p] of [
    ["POST", "/godotLink/token"],
    ["GET", "/godotLink/epic"],
    ["POST", "/godotLink/update"],
  ]) {
    const r = await invoke(m, p, { token: "tok-admin", body: { projectId: "p1" } });
    assert.strictEqual(r.statusCode, 404, `Expected 404 for ${m} ${p}, got ${r.statusCode}`);
  }

  // 4. Proxy route policy checks (model allowlist, method, payload cap, auth).
  const blockedModel = await invoke("POST", "/v1beta/models/gemini-pro:generateContent", {
    token: "tok-admin",
    body: {},
  });
  assert.strictEqual(blockedModel.statusCode, 403);

  const wrongMethod = await invoke("GET", "/v1beta/models/gemini-4-hydrogen:generateContent", {
    token: "tok-admin",
  });
  assert.strictEqual(wrongMethod.statusCode, 405);

  const tooBig = await invoke("POST", "/v1beta/models/gemini-4-hydrogen:generateContent", {
    token: "tok-admin",
    rawBytes: helpers.MAX_BODY_BYTES + 1,
  });
  assert.strictEqual(tooBig.statusCode, 413);

  const missingAuth = await invoke("POST", "/v1beta/models/gemini-4-hydrogen:generateContent", {
    body: { contents: [] },
  });
  assert.strictEqual(missingAuth.statusCode, 401);

  const uninvitedProxy = await invoke("POST", "/v1beta/models/gemini-4-hydrogen:generateContent", {
    token: "tok-uninvited",
    body: { contents: [] },
  });
  assert.strictEqual(uninvitedProxy.statusCode, 403);

  const okProxy = await invoke("POST", "/v1beta/models/gemini-4-hydrogen:generateContent", {
    token: "tok-approved",
    body: { contents: [{ parts: [{ text: "hi" }] }] },
  });
  assert.strictEqual(okProxy.statusCode, 200);
  assert.strictEqual(fetchCalls.length, 1);
  assert.strictEqual(
    fetchCalls[0].opts.headers["x-goog-api-key"],
    "test-gemini-secret"
  );

  // 5. Invite & access control routes.
  const sendForbidden = await invoke("POST", "/sendInvite", {
    token: "tok-approved",
    body: { email: "newdev@studio.dev" },
  });
  assert.strictEqual(sendForbidden.statusCode, 403);

  const sendOk = await invoke("POST", "/sendInvite", {
    token: "tok-admin",
    body: { email: "newdev@studio.dev" },
  });
  assert.strictEqual(sendOk.statusCode, 200);
  assert.strictEqual(sendOk.body.status, "invited");

  const mismatch = await invoke("POST", "/acceptInvite", {
    token: "tok-invited",
    body: { invitedEmail: "other@studio.dev" },
  });
  assert.strictEqual(mismatch.statusCode, 409);

  const acceptOk = await invoke("POST", "/acceptInvite", {
    token: "tok-invited",
    body: { invitedEmail: "invited@studio.dev" },
  });
  assert.strictEqual(acceptOk.statusCode, 200);
  assert.strictEqual(acceptOk.body.status, "approved");
  assert.strictEqual(acceptOk.body.newlyAccepted, true);

  const uninvitedAccept = await invoke("POST", "/acceptInvite", {
    token: "tok-uninvited",
    body: {},
  });
  assert.strictEqual(uninvitedAccept.statusCode, 403);
  assert(deletedUids.includes("u-uninv"));

  const revokeOk = await invoke("POST", "/revokeInvite", {
    token: "tok-admin",
    body: { email: "approved@studio.dev" },
  });
  assert.strictEqual(revokeOk.statusCode, 200);
  assert.strictEqual(revokeOk.body.status, "revoked");
  assert(revokedUids.includes("u-app"));

  console.log("CLOUD_PROXY_TEST_OK");
})().catch((err) => {
  console.error(err);
  process.exit(1);
});
"""


def main() -> int:
  proc = subprocess.run(
      ["node", "-e", NODE_TEST, ROOT],
      cwd=ROOT,
      capture_output=True,
      text=True,
  )
  if proc.stdout:
    print(proc.stdout.strip())
  if proc.stderr:
    print(proc.stderr.strip(), file=sys.stderr)
  return proc.returncode


if __name__ == "__main__":
  sys.exit(main())
