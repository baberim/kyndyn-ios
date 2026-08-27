# Build 32 — Premium foundation

Build 32 defines Kyndyn's paid offering before StoreKit products are created.
It does not remove an existing feature, create an App Store Connect product, or
claim that a purchase exists.

## Launch pricing

- Monthly: **$3.99 USD**
- Annual: **$29.99 USD**, presented as the recommended option
- Introductory trial: **14 days**
- Apple Family Sharing: enabled for both subscription products
- Lifetime purchase: intentionally deferred until retention and ongoing service
  costs are understood

Prices outside the United States will use App Store Connect's localized price
tiers. Final product creation remains a manual App Store Connect action.

## Free forever

Kyndyn's useful family loop stays free:

- one household and family profiles;
- quest creation, assignment, recurrence, completion, and exact undo;
- XP, levels, streaks, badges, and the current family reward;
- iCloud household sharing and synchronization;
- local-only use, reminders, security, accessibility, backup, restore, and
  recovery;
- basic Siri actions and access to all previously created household data.

No child-facing screen asks for a purchase. Security, accessibility, backup,
recovery, and access to existing family information are never paywalled.

## Premium expansion

Premium is reserved for optional convenience and delight:

- Apple Watch companion;
- advanced planning, reusable templates, and recurrence tools;
- richer family insights;
- expanded visual customization and collections;
- enhanced calendar and weather context;
- widgets and Live Activities;
- advanced Siri and Shortcuts automations.

Individual features remain subject to validation in their own builds. Listing a
feature here does not advertise it as shipped.

## Entitlement rules

- StoreKit's verified transaction state will be the source of purchase truth.
- Direct purchases, Apple Family Sharing, complimentary access, and explicitly
  grandfathered access are represented separately for support diagnostics.
- Active and Apple-provided grace-period states permit new premium actions.
- Expired, refunded, or revoked access stops new premium-only actions but never
  deletes, conceals, or corrupts existing household data or earned items.
- Restore Purchases will be visible to adults and will re-check verified
  StoreKit transactions; Kyndyn will not invent its own account password.
- Apple Family Sharing covers the purchaser's Apple family. A participant in a
  Kyndyn CloudKit household is not automatically proven to be part of that Apple
  family.
- Complimentary access will use App Store offer codes or a separately approved,
  auditable entitlement mechanism. It will not be a hidden client-side switch.
- Product identifiers, pricing, trial configuration, and Family Sharing are not
  created or changed by this build.

## Proposed StoreKit products

The next StoreKit build should use one subscription group and two auto-renewable
products:

- `com.kyndynfamily.kyndyn.premium.monthly`
- `com.kyndynfamily.kyndyn.premium.annual`

These identifiers are proposals until created in App Store Connect. Family
Sharing cannot be disabled after it is enabled for an in-app purchase, so that
external action requires an explicit final confirmation.

## Testing boundary

Build 32 adds deterministic entitlement states and tests the most important
expiration promise: losing premium never makes existing household data
unreadable. Build 33 can add StoreKit 2 purchase, restore, transaction update,
offline cache, and local StoreKit configuration tests against these rules.
