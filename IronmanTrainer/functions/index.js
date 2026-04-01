const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();
const db = admin.firestore();

// Configure SMTP — set via .env file in functions/
const transporter = nodemailer.createTransport({
  service: "gmail",
  auth: {
    user: process.env.SMTP_EMAIL || "",
    pass: process.env.SMTP_PASSWORD || "",
  },
});

// Generate a 6-digit OTP
function generateOTP() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

// CORS helper
function setCors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
}

// Request OTP — generates code, stores in Firestore, sends email
exports.requestOTP = onRequest(async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method not allowed" }); return; }

  try {
    const email = req.body.email;
    if (!email || !email.includes("@")) {
      res.status(400).json({ error: "Valid email required." });
      return;
    }

    const otp = generateOTP();
    const expiresAt = Date.now() + 10 * 60 * 1000; // 10 minutes

    // Store OTP in Firestore
    await db.collection("otpCodes").doc(email.toLowerCase()).set({
      code: otp,
      email: email.toLowerCase(),
      expiresAt,
      attempts: 0,
      createdAt: Date.now(),
    });

    // Send email
    const smtpConfigured = process.env.SMTP_EMAIL && process.env.SMTP_PASSWORD;
    if (smtpConfigured) {
      try {
        await transporter.sendMail({
          from: `"Ironman Trainer" <${process.env.SMTP_EMAIL}>`,
          to: email,
          subject: "Your Ironman Trainer sign-in code",
          text: `Your verification code is: ${otp}\n\nThis code expires in 10 minutes.`,
          html: `
            <div style="font-family: -apple-system, sans-serif; max-width: 400px; margin: 0 auto; padding: 20px;">
              <h2>Ironman Trainer</h2>
              <p>Your verification code is:</p>
              <div style="font-size: 32px; font-weight: bold; letter-spacing: 8px; text-align: center; padding: 20px; background: #f0f0f0; border-radius: 8px; margin: 16px 0;">
                ${otp}
              </div>
              <p style="color: #666; font-size: 14px;">This code expires in 10 minutes.</p>
            </div>
          `,
        });
      } catch (err) {
        console.error("Email send failed:", err);
      }
    }

    // Always log OTP for development/testing
    console.log(`OTP for ${email}: ${otp}`);

    res.status(200).json({ success: true, message: "Verification code sent." });
  } catch (err) {
    console.error("requestOTP error:", err);
    res.status(500).json({ error: "Internal error." });
  }
});

// Verify OTP — checks code, creates custom auth token
exports.verifyOTP = onRequest(async (req, res) => {
  setCors(res);
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }
  if (req.method !== "POST") { res.status(405).json({ error: "Method not allowed" }); return; }

  try {
    const { email, code } = req.body;
    if (!email || !code) {
      res.status(400).json({ error: "Email and code required." });
      return;
    }

    const docRef = db.collection("otpCodes").doc(email.toLowerCase());
    const doc = await docRef.get();

    if (!doc.exists) {
      res.status(404).json({ error: "No verification code found. Request a new one." });
      return;
    }

    const data = doc.data();

    // Check expiry
    if (Date.now() > data.expiresAt) {
      await docRef.delete();
      res.status(410).json({ error: "Code expired. Request a new one." });
      return;
    }

    // Check attempts (max 5)
    if (data.attempts >= 5) {
      await docRef.delete();
      res.status(429).json({ error: "Too many attempts. Request a new code." });
      return;
    }

    // Increment attempts
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });

    // Verify code
    if (data.code !== code) {
      res.status(401).json({ error: "Incorrect code." });
      return;
    }

    // Code is valid — clean up and create auth token
    await docRef.delete();

    // Get or create Firebase Auth user for this email
    const emailLower = email.toLowerCase();
    let uid;
    try {
      const user = await admin.auth().getUserByEmail(emailLower);
      uid = user.uid;
    } catch (err) {
      const newUser = await admin.auth().createUser({
        email: emailLower,
        emailVerified: true,
      });
      uid = newUser.uid;
    }

    const token = await admin.auth().createCustomToken(uid);
    res.status(200).json({ success: true, token });
  } catch (err) {
    console.error("verifyOTP error:", err.message, err.code, err.stack);
    res.status(500).json({ error: err.message || "Internal error." });
  }
});
