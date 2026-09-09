# App Review follow-up — build 37 StoreKit-native subscription fix

Build 36 exposed a StoreKit presentation race during local iPad testing: a
purchase request could report “Unable to Complete Request” before Apple's
confirmation UI appeared, and the old error remained visible even after the
verified subscription became active.

Build 37 removes Kyndyn's custom purchase initiation controls. The Premium
screen now uses Apple's `SubscriptionStoreView`, which loads, displays, and
purchases both auto-renewable subscriptions as one StoreKit-owned workflow.
Kyndyn continues to verify transactions and derive access from current App Store
entitlements.

The entitlement state is now explicitly authoritative over presentation errors.
Whenever a verified active or grace-period entitlement is received, any older
StoreKit error is cleared. Purchase completion also reconciles current
entitlements before surfacing a StoreKit failure, covering delayed transaction
delivery.

## Draft reply to App Review

Hello App Review,

We performed an additional iPad purchase-flow audit after build 36 and found a
StoreKit presentation race that could leave an error visible even when Apple
subsequently completed the subscription.

In build 37, the Premium screen now uses Apple's native SubscriptionStoreView
for product loading, plan presentation, purchase confirmation, and restoration.
This removes Kyndyn's custom purchase-presentation path entirely. We also made
verified App Store entitlement state authoritative over earlier presentation
errors, so a completed subscription immediately clears any stale error and
shows Premium as active.

Both the monthly and annual subscriptions are included with this version. To
reach the screen, complete the short household setup if prompted, open Parent,
unlock it when prompted, and select Kyndyn Premium. No account sign-in is
required.

Thank you.
