const crypto = require("crypto");
const nodemailer = require("nodemailer");

const ACCESS_CACHE_TTL_MS = 15 * 1000;

function parseAdminEmails() {
  return new Set(
    String(process.env.ADMIN_EMAILS || "henryyoungchoi@gmail.com")
      .split(",")
      .map((s) => s.trim().toLowerCase())
      .filter(Boolean)
  );
}

function isAdminEmail(email) {
  return parseAdminEmails().has(String(email || "").trim().toLowerCase());
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) && email.length <= 254;
}

function parseJsonBody(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string" && req.body.trim()) {
    try {
      return JSON.parse(req.body);
    } catch (_) {
      return {};
    }
  }
  if (req.rawBody) {
    try {
      return JSON.parse(req.rawBody.toString("utf8"));
    } catch (_) {
      return {};
    }
  }
  return {};
}

function createAuthAccessControl({
  getAuth,
  getFirestore,
  FieldValue,
  gmailAppPasswordSecret,
  defaultWebStudioUrl,
  extractBearerLinkToken,
  hashLinkToken,
}) {
  const DEFAULT_WEB_STUDIO_URL = defaultWebStudioUrl;
  const accessCache = new Map();

  async function verifyGodotLinkToken(req) {
    const rawToken = extractBearerLinkToken(req);
    if (!rawToken) {
      return {
        errorStatus: 401,
        errorMessage: "Missing or invalid Godot Project Link Token (lyr_...).",
      };
    }
    const tokenHash = hashLinkToken(rawToken);
    const snap = await getFirestore()
      .collection("godot_links")
      .where("tokenHash", "==", tokenHash)
      .limit(1)
      .get();
    if (snap.empty) {
      return {
        errorStatus: 401,
        errorMessage: "Invalid or expired Godot Project Link Token.",
      };
    }
    const linkDoc = snap.docs[0];
    const data = linkDoc.data() || {};
    if (data.revoked === true || !data.uid || !data.projectId) {
      return {
        errorStatus: 401,
        errorMessage: "This Godot Project Link Token has been revoked.",
      };
    }
    const email = String(data.email || "").trim().toLowerCase();
    if (!email) {
      return {
        errorStatus: 403,
        errorMessage: "Linked account email is missing.",
      };
    }
    if (!isAdminEmail(email)) {
      const status = await getAccessStatusFromDb(email);
      if (status !== "approved") {
        return {
          errorStatus: 403,
          errorMessage: `Invite approval required for ${email}.`,
        };
      }
    }
    return {
      uid: String(data.uid),
      email,
      projectId: String(data.projectId),
      webStudioUrl: String(data.webStudioUrl || DEFAULT_WEB_STUDIO_URL),
      linkRef: linkDoc.ref,
    };
  }

  function setCachedStatus(email, status) {
    accessCache.set(email, {
      status,
      expiresAt: Date.now() + ACCESS_CACHE_TTL_MS,
    });
  }
  
  function clearCachedStatus(email) {
    accessCache.delete(email);
  }
  
  async function getAccessStatusFromDb(email) {
    const cached = accessCache.get(email);
    if (cached && cached.expiresAt > Date.now()) {
      return cached.status;
    }
    const snap = await getFirestore().collection("ai_access").doc(email).get();
    const status = snap.exists ? String(snap.data()?.status || "uninvited") : "uninvited";
    setCachedStatus(email, status);
    return status;
  }
  
  async function verifyCallerToken(req) {
    const authHeader = String(req.headers.authorization || "");
    if (!authHeader.startsWith("Bearer ")) {
      return { errorStatus: 401, errorMessage: "Missing Firebase Authorization Bearer token." };
    }
    const idToken = authHeader.slice("Bearer ".length).trim();
    if (!idToken) {
      return { errorStatus: 401, errorMessage: "Empty Bearer token." };
    }
    try {
      // checkRevoked = true ensures revoked users lose token access immediately
      const decoded = await getAuth().verifyIdToken(idToken, true);
      const email = String(decoded.email || "").trim().toLowerCase();
      if (!email || decoded.email_verified === false) {
        return { errorStatus: 403, errorMessage: "A verified Google account email is required." };
      }
      return {
        uid: decoded.uid,
        email,
        displayName: String(decoded.name || "").trim(),
      };
    } catch (_err) {
      return { errorStatus: 401, errorMessage: "Invalid, expired, or revoked Google Sign-In token." };
    }
  }

  async function sendInviteEmailIfConfigured({ toEmail, inviteUrl, invitedBy }) {
    const rawPass = String(gmailAppPasswordSecret.value() || "").replace(/\s+/g, "");
    if (!rawPass) {
      return { emailSent: false, reason: "smtp_not_configured" };
    }
    const fromEmail = String(
      process.env.SMTP_FROM_EMAIL || invitedBy || "henryyoungchoi@gmail.com"
    ).trim();
  
    const transporter = nodemailer.createTransport({
      host: "smtp.gmail.com",
      port: 465,
      secure: true,
      auth: {
        user: fromEmail,
        pass: rawPass,
      },
    });
  
    const html = `
      <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 520px; margin: 24px auto; padding: 28px; background: #12151B; color: #F3F4F6; border: 1px solid #262C36; border-radius: 10px;">
        <div style="font-family: monospace; font-size: 11px; letter-spacing: 1px; color: #10B981; font-weight: 700; margin-bottom: 10px;">LAYERS-AGENTIC STUDIO</div>
        <h2 style="margin: 0 0 12px 0; font-size: 20px; color: #FFFFFF;">You've been invited to LAYERS-Agentic</h2>
        <p style="margin: 0 0 20px 0; font-size: 14px; line-height: 1.55; color: #9CA3AF;">
          <strong>${invitedBy}</strong> invited <strong>${toEmail}</strong> to collaborate and build with Gemini 4 Hydrogen in LAYERS-Agentic.
        </p>
        <a href="${inviteUrl}" style="display: inline-block; padding: 11px 20px; background: #10B981; color: #06281E; text-decoration: none; font-weight: 700; font-size: 14px; border-radius: 6px;">
          Accept Invite &amp; Sign in with Google &rarr;
        </a>
        <p style="margin: 22px 0 0 0; font-size: 12px; line-height: 1.5; color: #6B7280;">
          Sign in using <strong>${toEmail}</strong> when prompted. If the button doesn't open, copy and paste this link:<br/>
          <span style="color: #9CA3AF; word-break: break-all;">${inviteUrl}</span>
        </p>
      </div>
    `;
  
    try {
      await transporter.sendMail({
        from: `"LAYERS-Agentic" <${fromEmail}>`,
        to: toEmail,
        subject: "You're invited to LAYERS-Agentic",
        text: `${invitedBy} invited you (${toEmail}) to LAYERS-Agentic.\n\nAccept your invite and sign in with Google:\n${inviteUrl}\n`,
        html,
      });
      return { emailSent: true };
    } catch (err) {
      return {
        emailSent: false,
        reason: String(err && err.message ? err.message : err),
      };
    }
  }

  async function handleInviteAdminRoutes(req, res, cleanPath) {
  if (cleanPath === "/sendInvite") {
    if (req.method !== "POST") {
      res.status(405).json({ error: { code: 405, message: "Expected POST." } });
      return true;
    }
    const caller = await verifyCallerToken(req);
    if (caller.errorStatus) {
      res.status(caller.errorStatus).json({
        error: { code: caller.errorStatus, message: caller.errorMessage },
      });
      return true;
    }
    if (!isAdminEmail(caller.email)) {
      res.status(403).json({
        error: { code: 403, message: "Only workspace admins can send invites." },
      });
      return true;
    }

    const body = parseJsonBody(req);
    const targetEmail = String(body.email || "").trim().toLowerCase();
    if (!isValidEmail(targetEmail)) {
      res.status(400).json({
        error: { code: 400, message: "Please enter a valid email address." },
      });
      return true;
    }
    if (isAdminEmail(targetEmail)) {
      res.status(400).json({
        error: { code: 400, message: "Admin owner already has full access." },
      });
      return true;
    }

    const inviteToken = crypto.randomBytes(24).toString("hex");
    const baseAppUrl = String(
      process.env.APP_PUBLIC_URL || "https://henrycgithub.github.io/LAYERS-Agentic/"
    ).replace(/\/+$/, "");
    const inviteUrl = `${baseAppUrl}/?invite=${inviteToken}&invited_email=${encodeURIComponent(
      targetEmail
    )}`;
    const nowMs = Date.now();

    const docRef = getFirestore().collection("ai_access").doc(targetEmail);
    const existing = await docRef.get();
    const prevStatus = existing.exists ? existing.data()?.status : null;
    const keepApproved = prevStatus === "approved" && body.resetStatus !== true;

    await docRef.set(
      {
        email: targetEmail,
        status: keepApproved ? "approved" : "invited",
        inviteToken,
        inviteUrl,
        invitedBy: caller.email,
        invitedAt: nowMs,
        updatedAt: nowMs,
      },
      { merge: true }
    );
    clearCachedStatus(targetEmail);

    const mailResult = await sendInviteEmailIfConfigured({
      toEmail: targetEmail,
      inviteUrl,
      invitedBy: caller.email,
    });

    res.status(200).json({
      ok: true,
      email: targetEmail,
      status: keepApproved ? "approved" : "invited",
      emailSent: mailResult.emailSent,
      emailNotice: mailResult.reason || null,
      inviteUrl,
    });
    return true;
  }

  // -------------------------------------------------------------------------
  // Route 2: POST /acceptInvite (Verifies or activates invited Google login)
  // -------------------------------------------------------------------------
  if (cleanPath === "/acceptInvite") {
    if (req.method !== "POST") {
      res.status(405).json({ error: { code: 405, message: "Expected POST." } });
      return true;
    }
    const caller = await verifyCallerToken(req);
    if (caller.errorStatus) {
      res.status(caller.errorStatus).json({
        error: { code: caller.errorStatus, message: caller.errorMessage },
      });
      return true;
    }

    if (isAdminEmail(caller.email)) {
      res.status(200).json({
        ok: true,
        email: caller.email,
        status: "approved",
        isAdmin: true,
      });
      return true;
    }

    const body = parseJsonBody(req);
    const expectedEmail = String(body.invitedEmail || "").trim().toLowerCase();
    const db = getFirestore();
    const callerRef = db.collection("ai_access").doc(caller.email);
    const callerSnap = await callerRef.get();
    const callerStatus = callerSnap.exists
      ? String(callerSnap.data()?.status || "uninvited")
      : "uninvited";

    // Guard: clicked an invite link sent to Email A while signed into Google Account B
    if (expectedEmail && expectedEmail !== caller.email) {
      if (callerStatus !== "approved" && callerStatus !== "invited") {
        await getAuth().deleteUser(caller.uid).catch(() => {});
      }
      res.status(409).json({
        ok: false,
        code: "email_mismatch",
        expectedEmail,
        signedInEmail: caller.email,
        error: {
          code: 409,
          message: `This invite was sent to ${expectedEmail}, but you signed in as ${caller.email}. Please sign in with ${expectedEmail}.`,
        },
      });
      return true;
    }

    const nowMs = Date.now();
    if (callerStatus === "approved") {
      await callerRef.set(
        {
          uid: caller.uid,
          displayName: caller.displayName || callerSnap.data()?.displayName || "",
          lastLoginAt: nowMs,
          updatedAt: nowMs,
        },
        { merge: true }
      );
      setCachedStatus(caller.email, "approved");
      res.status(200).json({
        ok: true,
        email: caller.email,
        status: "approved",
        newlyAccepted: false,
      });
      return true;
    }

    if (callerStatus === "invited") {
      await callerRef.set(
        {
          status: "approved",
          uid: caller.uid,
          displayName: caller.displayName || "",
          inviteToken: null,
          acceptedAt: nowMs,
          lastLoginAt: nowMs,
          updatedAt: nowMs,
        },
        { merge: true }
      );
      setCachedStatus(caller.email, "approved");
      res.status(200).json({
        ok: true,
        email: caller.email,
        status: "approved",
        newlyAccepted: true,
      });
      return true;
    }

    // Uninvited or revoked Google account: purge from Firebase Auth Users to keep list clean
    await getAuth().deleteUser(caller.uid).catch(() => {});
    clearCachedStatus(caller.email);
    res.status(403).json({
      ok: false,
      code: callerStatus === "revoked" ? "revoked" : "uninvited",
      status: callerStatus,
      error: {
        code: 403,
        message:
          callerStatus === "revoked"
            ? `Access for ${caller.email} has been revoked by the workspace admin.`
            : `Invite required — ${caller.email} has not been invited to this workspace yet.`,
      },
    });
    return true;
  }

  // -------------------------------------------------------------------------
  // Route 3: POST /revokeInvite (Admin-only: cancels pending invite or revokes active user)
  // -------------------------------------------------------------------------
  if (cleanPath === "/revokeInvite") {
    if (req.method !== "POST") {
      res.status(405).json({ error: { code: 405, message: "Expected POST." } });
      return true;
    }
    const caller = await verifyCallerToken(req);
    if (caller.errorStatus) {
      res.status(caller.errorStatus).json({
        error: { code: caller.errorStatus, message: caller.errorMessage },
      });
      return true;
    }
    if (!isAdminEmail(caller.email)) {
      res.status(403).json({
        error: { code: 403, message: "Only workspace admins can revoke access." },
      });
      return true;
    }

    const body = parseJsonBody(req);
    const targetEmail = String(body.email || "").trim().toLowerCase();
    if (!isValidEmail(targetEmail) || isAdminEmail(targetEmail)) {
      res.status(400).json({
        error: { code: 400, message: "Invalid target email." },
      });
      return true;
    }

    const nowMs = Date.now();
    const docRef = getFirestore().collection("ai_access").doc(targetEmail);
    await docRef.set(
      {
        email: targetEmail,
        status: "revoked",
        inviteToken: null,
        revokedBy: caller.email,
        revokedAt: nowMs,
        updatedAt: nowMs,
      },
      { merge: true }
    );
    clearCachedStatus(targetEmail);

    try {
      const userRecord = await getAuth().getUserByEmail(targetEmail);
      await getAuth().revokeRefreshTokens(userRecord.uid).catch(() => {});
      await getAuth().deleteUser(userRecord.uid).catch(() => {});
    } catch (_) {
      // User had not signed into Firebase Auth yet
    }

    res.status(200).json({
      ok: true,
      email: targetEmail,
      status: "revoked",
    });
    return true;
  }
    return false;
  }

  return {
    verifyGodotLinkToken,
    getAccessStatusFromDb,
    verifyCallerToken,
    handleInviteAdminRoutes,
  };
}

module.exports = {
  parseAdminEmails,
  isAdminEmail,
  isValidEmail,
  parseJsonBody,
  createAuthAccessControl,
};
