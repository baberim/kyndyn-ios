# kyndyn notification service

This directory contains the Cloudflare Worker planned for hosted kyndyn family
notifications. The first deployment is deliberately limited to a content-free
`GET /health` response. All `/v1/` operations return `503` until authenticated
device registration, privacy controls, and APNs delivery are
implemented and reviewed.

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

- no device tokens are accepted or stored;
- no notification payloads can be submitted;
- no APNs connection is attempted;
- no household or person information is logged;
- the D1 binding is configured, but migrations remain an explicit reviewed
  deployment step.
