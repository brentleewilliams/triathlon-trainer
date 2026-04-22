---
layout: default
title: Privacy Policy
---

# Privacy Policy for Race1 Trainer

**Effective date:** April 22, 2026
**Last updated:** April 22, 2026

Race1 Trainer ("the app", "we", "us") is an AI-powered training companion for endurance athletes. This policy explains what data the app collects, how it's used, and who it's shared with. We've written it in plain English.

If you have questions, contact us at **brentleewilliams@gmail.com**.

## 1. What we collect

### Account information
When you sign in with Apple or email, we receive:
- A Firebase-issued user ID
- Your email address (for email sign-in) or an anonymized Apple relay address (for Sign in with Apple)

We do not collect passwords directly — authentication is handled by Firebase Authentication (Google).

### Health data (Apple HealthKit)
With your permission, the app reads:
- Workout history (last 30 days, for plan adherence)
- Heart rate samples (for training zone analytics)
- Date of birth (to calculate your maximum heart rate)
- Sleep analysis (for the Morning Check-In feature)

**Apple HealthKit data stays on your device.** It is not uploaded to our servers, transmitted to third parties, or used for advertising. You can revoke HealthKit access anytime in the iOS Settings app under Privacy → Health.

### Training plan and chat data
When you interact with the AI coach, we collect and store:
- Race goal, race date, experience level, weekly schedule, and any information you share during onboarding
- Generated training plans and any edits you approve
- Messages you send to your coach and the coach's responses
- Performance thresholds (FTP, threshold pace, swim CSS) if you choose to share them
- Completed workouts matched against your plan

### Location data (optional)
On first launch, with your permission, the app uses CoreLocation to infer your training elevation and climate. Only your approximate admin area (e.g. "Oregon") and current altitude are used, and only at the moment you grant permission — we do not track your location over time. You can override this manually in Settings at any time.

### Device information
- An Apple Push Notification / Firebase Cloud Messaging token, if you enable notifications, so we can deliver Morning Check-In reminders
- Standard iOS device metadata (OS version, device model, app version) for crash reporting and analytics

### Automatically collected
- Crash reports and basic usage analytics via Firebase Analytics
- Error logs from our AI coaching pipeline

## 2. How we use your data

- **Generate and adapt your training plan.** Your race, schedule, workout history, and chat messages are sent to our AI coaching service to produce a personalized plan and to revise it when you ask.
- **Morning Check-In.** Sleep duration from HealthKit is combined with your plan to generate a conversational check-in each morning.
- **Coaching chat.** Your messages and relevant context (current week, recent workouts, race course details) are sent to our AI provider so the coach can respond.
- **Improve the product.** We review aggregate usage patterns and error logs. We may review individual chat transcripts **only** when you report a bug or request support.
- **Deliver notifications.** With your permission, we schedule local and push reminders for workouts and check-ins.

We **do not** use your data for advertising, sell your data, or share it with data brokers.

## 3. Third-party services

The app depends on the following services. Each has its own privacy policy:

| Service | Provider | Purpose |
|---|---|---|
| Firebase Authentication | Google | Sign-in and account management |
| Firebase Firestore | Google | Storing your training plan versions |
| Firebase Cloud Functions | Google | Server-side AI coaching proxy |
| Firebase Cloud Messaging | Google | Push notifications |
| Firebase Analytics / Crashlytics | Google | Anonymous usage analytics and crash reports |
| Claude API | Anthropic PBC | AI coaching responses |
| OpenAI API | OpenAI | Supplemental AI features (race research, plan generation) |
| LangSmith | Anthropic | Logging prompt and response traces for debugging and quality |

When you chat with your coach, the content of your messages is sent to Anthropic and/or OpenAI to generate responses. Under these providers' standard business terms, API traffic is not used to train their models. Traces stored in LangSmith are retained for debugging purposes and are accessible only to our engineering team.

Apple HealthKit data is never sent to any of the services above.

## 4. Where your data is stored

- Your training plan, chat history, and app preferences are stored both **locally on your device** (Core Data and UserDefaults) and in **Firestore** (Google's hosted database, US region).
- HealthKit data stays on your device.
- Authentication data is stored by Firebase Authentication.
- AI chat traces are stored in LangSmith (US region) for up to 90 days.

## 5. Data retention and deletion

- You can clear your chat history anytime from **Settings → Clear History** inside the app.
- You can request deletion of your account and all associated data by emailing **brentleewilliams@gmail.com**. We will delete your Firestore data and revoke your Firebase account within 30 days.
- Uninstalling the app removes local data from your device but does not delete Firestore or authentication records.

## 6. Children's privacy

Race1 Trainer is not directed at children under 13, and we do not knowingly collect personal information from anyone under 13. If you believe a child has provided us with personal information, contact us and we will delete it.

## 7. Your rights

Depending on where you live, you may have rights to:
- Access the personal data we hold about you
- Correct inaccurate data
- Request deletion of your data
- Opt out of processing

To exercise any of these rights, email us at **brentleewilliams@gmail.com**. We respond within 30 days.

**California residents:** You have rights under the CCPA / CPRA, including the right to know, the right to delete, and the right to opt out of the "sale" of personal information. We do not sell personal information.

**EU / UK residents:** We rely on the following legal bases under GDPR: performance of a contract (to provide the training service), legitimate interests (to improve the product and debug), and consent (for optional features like location and health data).

## 8. Security

We use industry-standard security measures, including encrypted transit (HTTPS/TLS) and encryption at rest for Firestore data. Firebase Authentication secures account credentials. No online service is 100% secure; we cannot guarantee absolute security.

## 9. Changes to this policy

We may update this policy over time. When we do, we'll post the new version here and update the "Last updated" date. Material changes will be surfaced in-app before they take effect.

## 10. Contact

Questions or requests:
**brentleewilliams@gmail.com**
