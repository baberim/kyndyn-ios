# Build 33 — StoreKit implementation

Build 33 connects the approved premium rules to StoreKit 2 without enabling or
changing any live App Store product.

## Implemented

- Loads localized monthly and annual products from Apple.
- Purchases only through StoreKit and accepts only verified transactions.
- Listens for transaction changes while Kyndyn is running.
- Restores purchases through `AppStore.sync()`.
- Recognizes direct and Apple Family Sharing ownership separately.
- Represents active, grace-period, billing-retry, expired, and revoked states.
- Keeps a bounded local cache of a previously verified, unexpired entitlement
  for offline startup.
- Places plan and restore controls inside the authenticated Parent area so
  children are not shown purchase prompts.
- Keeps every shipped family feature available when products are absent.
- Never deletes or hides family data when premium expires or is revoked.

## Product identifiers

- `com.kyndynfamily.kyndyn.premium.monthly`
- `com.kyndynfamily.kyndyn.premium.annual`

Both belong in one subscription group named **Kyndyn Premium**. Proposed US
pricing remains $3.99 monthly and $29.99 annually. Configure a 14-day free trial
for each product; Apple permits each customer one introductory offer per
subscription group.

## Local StoreKit testing

The product definitions remain an Apple/Xcode configuration boundary. In Xcode:

1. Choose **File → New → File from Template**.
2. Select **StoreKit Configuration File**, name it `Kyndyn`, and leave syncing
   with App Store Connect off until the products exist there.
3. Add one auto-renewable subscription group named `Kyndyn Premium`.
4. Add monthly and annual subscriptions using the identifiers above, prices
   $3.99 and $29.99, and a 14-day free trial.
5. In **Product → Scheme → Edit Scheme → Run → Options**, select the new
   StoreKit configuration.

This local file can exercise purchase, renewal, expiration, refund, interrupted
purchase, and Family Sharing-style ownership without spending money. Do not use
real personal purchase data in screenshots or test fixtures.

## App Store Connect boundary

After local testing, create the subscription group and products in App Store
Connect, add localization and review information, configure the trial, and
explicitly enable Family Sharing. Apple does not allow Family Sharing to be
disabled for that in-app purchase after it is enabled, so that final switch
requires owner confirmation.
