# Build 27 — Hosted family notifications

Build 27 introduces a minimal Cloudflare Worker and D1 boundary for dependable,
explicitly approved family notifications. It does not replace CloudKit sync or
device-local quest reminders.

## Delivery categories

- CloudKit synchronization notifications remain private change hints handled by
  the existing sync coordinator.
- Quest reminders remain device-local and continue to respect local targeting,
  quiet hours, and lock-screen privacy.
- Hosted APNs delivery is reserved for visible family announcements and future
  alerts that a parent explicitly enables.

## Implemented state

The Worker exposes a content-free health check and a capability-authenticated
enrollment boundary. Its D1 binding and reviewed schema migrations are
versioned with the Worker, but migrations
are applied explicitly rather than during ordinary code deployment.
Device enrollment now uses separate random household capabilities, encrypted
APNs-token storage, bounded rate limits, request timestamps, and single-use
nonces. Broadcast submission and APNs delivery are active behind encrypted
Worker secrets. Participant devices use short-lived, single-use pairing codes and
receive only a device-specific revocable credential. They never receive the
household admin or owner enrollment capability.

The iOS app lets the household owner enable push delivery from the protected
Announcements area, create a ten-minute one-use pairing code, and copy it to an
invited device. A family device enters that code under Reminders, stores only
its revocable device credential in the device-only Keychain, refreshes its APNs
token after relaunch, and can disconnect itself. Publishing a new announcement
attempts hosted delivery but never rolls back or blocks the local/CloudKit save
when the network or notification service is unavailable.

Future operations work includes cost/failure monitoring, capability rotation,
and a protected household-wide device-management surface.

The Worker already routes Sandbox and Production tokens separately, rejects
oversized broadcast content, invalidates rejected device tokens, classifies
transient failures for bounded retry, and stores only content-free receipts.

## Apple configuration

- Team ID: `96TZPZ6H89`
- APNs topic: `com.kyndynfamily.kyndyn`
- Sandbox Key ID: `2K8PCHCCV8`
- Production Key ID: `G6L8MSV9F4`

These identifiers are not signing secrets. The corresponding `.p8` files remain
outside Git and are stored only as encrypted Cloudflare Worker secrets when the
service is ready to use them.

## Deployment

Cloudflare Workers Builds connects to the existing GitHub repository using
`/Services/Notifications` as the root directory. Production follows `main`;
pull-request builds may use Cloudflare preview versions. A Git deployment does
not deploy or modify the app's CloudKit production schema.

The D1 database ID is deployment configuration rather than a credential. Apple
private keys and the device-token encryption key remain encrypted Worker
secrets and never enter `wrangler.jsonc`, D1, Git, or build logs.

## Validation boundary

- Worker request, cryptography, APNs routing, pairing, replay protection, and
  validation behavior are covered by deterministic tests.
- The iOS target compiles and focused credential/identity tests use fictional
  values only.
- End-to-end APNs delivery must be tested on signed physical devices. The
  simulator cannot prove Apple push delivery.
- Production CloudKit is unrelated to this deployment and was not modified.
