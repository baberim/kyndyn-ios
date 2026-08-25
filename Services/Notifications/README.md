# kyndyn notification service

This directory contains the Cloudflare Worker planned for hosted kyndyn family
notifications. The first deployment is deliberately limited to a content-free
`GET /health` response. All `/v1/` operations return `503` until authenticated
device registration, D1 storage, privacy controls, and APNs delivery are
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

## Current safety state

- no device tokens are accepted or stored;
- no notification payloads can be submitted;
- no APNs connection is attempted;
- no household or person information is logged;
- no D1 database or production route is created by this scaffold.
