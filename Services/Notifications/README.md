# kyndyn notification service

This directory contains the Cloudflare Worker planned for hosted kyndyn family
notifications. It provides a content-free `GET /health` response plus
capability-authenticated household provisioning and encrypted device
registration/revocation. Owner-authorized family broadcasts route to the
matching APNs Sandbox or Production environment when both encrypted Apple
private-key secrets are configured.

## Git-connected bootstrap

In Cloudflare Workers & Pages, import `baberim/kyndyn-ios` and use:

- Worker name: `kyndyn-notifications`
- Production branch: `main`
- Root directory: `/Services/Notifications`
- Build command: `npm run check && npm test`
- Deploy command: `npx wrangler deploy`

Cloudflare preview deployments may be enabled for pull-request branches. The
Worker name must match the `name` in `wrangler.jsonc`.

## Secret boundary

The Apple Team ID, APNs topic, and APNs Key IDs are identifiers. The two `.p8`
private keys are secrets and must never be committed, pasted into issues or
logs, or stored in ordinary Worker variables. Add them only through encrypted
Cloudflare secrets after the authentication and D1 layers are ready:

- `APNS_SANDBOX_PRIVATE_KEY`
- `APNS_PRODUCTION_PRIVATE_KEY`
- `DEVICE_TOKEN_ENCRYPTION_KEY`

Local development files `.dev.vars` and `.env*` are ignored by Git. The checked
in `.env.example` contains identifiers only and no private material.

## D1 database

The `DB` binding points to `kyndyn-notifications-db`. Schema changes live in
`migrations/` and are never applied implicitly by a Worker deployment. After
reviewing a migration, apply it from this directory with:

```sh
npm run db:migrate:remote
```

The initial schema stores random household/device identifiers, one-way secret
and token hashes, encrypted APNs routing tokens, and content-free delivery
receipts. It does not contain household names, profile names, quest titles,
message bodies, PIN material, CloudKit credentials, calendar details, precise
location, or plaintext APNs device tokens.

## Current safety state

- device tokens are accepted only with a household enrollment capability and
  are encrypted before D1 storage;
- family broadcasts require the household admin capability and a fresh,
  single-use request;
- visible broadcast text is sent directly to APNs and is never persisted in
  D1 or application logs;
- delivery receipts contain identifiers and result categories only;
- invalid APNs tokens disable themselves and transient failures remain safely
  retryable under the same notification UUID;
- a household is limited to 16 active notification devices and 10 broadcast
  requests per minute;
- no household or person information is logged;
- requests use bounded rate limits, recent timestamps, and replay-resistant
  nonces;
- the D1 binding is configured, but migrations remain an explicit reviewed
  deployment step.

## Broadcast request boundary

`POST /v1/broadcasts` accepts a household UUID, stable notification UUID,
optional sender-device UUID, short title, short body, recent ISO-8601 timestamp,
and single-use nonce. The household admin capability is supplied as a bearer
token. Retrying the same notification UUID does not redeliver to devices that
already accepted or permanently rejected it.
