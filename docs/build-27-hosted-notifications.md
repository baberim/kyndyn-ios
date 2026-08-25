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

## Bootstrap state

The Worker exposes a content-free health check and a capability-authenticated
enrollment boundary. Its D1 binding and reviewed schema migrations are
versioned with the Worker, but migrations
are applied explicitly rather than during ordinary code deployment.
Device enrollment now uses separate random household capabilities, encrypted
APNs-token storage, bounded rate limits, request timestamps, and single-use
nonces. Broadcast submission and APNs delivery are implemented behind encrypted
Worker secrets and continue to fail closed until both Apple private keys are
installed. Participant devices use short-lived, single-use pairing codes and
receive only a device-specific revocable credential. They never receive the
household admin or owner enrollment capability. The remaining app-facing work
is:

1. iOS device enrollment and revocation wiring;
2. parent-facing broadcast permission and composition UI;
3. D1 storage with no names, quest titles, PIN material, CloudKit tokens,
   calendar details, precise location, plaintext device tokens, or message
   content in diagnostic logs;
4. parent-controlled categories, privacy copy, and opt-out behavior;
5. operating-cost and failure monitoring;
6. capability rotation and household-wide revocation controls.

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
