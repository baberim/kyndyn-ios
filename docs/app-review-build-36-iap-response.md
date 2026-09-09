# App Review follow-up — build 36 subscription purchase fix

Apple rejected version 1.0 (build 35), submission
`d9d5b4fb-84b8-4000-ad3d-ca721e501ca3`, under Guideline 2.1(b) after the
subscription buttons appeared to produce no action on an iPad Air 11-inch (M3)
running iPadOS 26.6.1.

## Code audit and correction

- Product identifiers are identical in production code and `Kyndyn.storekit`:
  `com.kyndynfamily.kyndyn.premium.monthly` and
  `com.kyndynfamily.kyndyn.premium.annual`.
- Product loading requests both identifiers and now treats an empty StoreKit
  response as an actionable availability error rather than a silent success.
- Purchasing now uses SwiftUI's environment `PurchaseAction`. StoreKit therefore
  receives the `UIWindowScene` containing the Premium view, instead of having to
  infer a presentation scene. This is important for iPad multi-window behavior.
- Purchase buttons now expand their labels to the full card width, making the
  complete visible button the hit target.
- A tap immediately changes the selected button to “Waiting for Apple…” with a
  spinner. Success, pending approval, cancellation, verification failure, and
  thrown StoreKit errors all produce visible status.
- Concurrent taps and restore/purchase overlap remain disabled. Verified
  transactions are finished before entitlement refresh. Transaction updates and
  current entitlements remain the source of truth.
- Restore now shows visible checking, restored, no-purchase, and failure states.
- No sheet or popover owned by Kyndyn is inserted between the active Premium view
  and StoreKit's confirmation UI.

## App Store Connect checks completed

- Paid Applications agreement is active; tax and banking setup has no pending
  action.
- Both product IDs exist under the same app and bundle ID
  `com.kyndynfamily.kyndyn`, in one auto-renewable subscription group.
- Each product and the subscription group are **Ready for Review**, with no
  missing metadata.
- Both IAPs are explicitly selected in version 1.0's **In-App Purchases and
  Subscriptions** section. For their first review, submit them with the app
  version; do not rely on merely creating them in App Store Connect.
- Subscription group and product localizations have non-empty display names and
  descriptions. Each product has review notes and a review screenshot showing
  the purchase control.
- Prices, all 175 availability territories, subscription durations, and the
  14-day introductory offers are saved and effective.
- Family Sharing matches the intended product policy in App Store Connect and
  the checked-in local StoreKit configuration.
- The signed 1.0 (36) archive was uploaded without attaching the local
  `Kyndyn.storekit` configuration. The corrected interaction was verified on an
  iPad Air 11-inch simulator with StoreKit test products.
- App Review notes explain the parent-only navigation path and that no account
  sign-in is required.

## Manual acceptance pass

1. Clean-install the candidate build and reach Parent → Kyndyn Premium on iPad.
2. Confirm both localized products and prices load from Apple's sandbox.
3. Tap every point across each full-width plan button. Confirm the button
   immediately shows progress and Apple's purchase sheet appears in the same
   window in portrait and landscape.
4. Exercise cancel, successful purchase, Ask to Buy/pending, offline/error, and
   interrupted purchase. Confirm each leaves visible, accurate status and never
   strands the controls in a disabled state.
5. Relaunch after purchase and confirm Premium remains active. Then test restore
   from a clean install and verify Family Sharing if it is enabled in App Store
   Connect.

## Draft reply to App Review

Hello App Review,

Thank you for identifying the subscription purchase issue in version 1.0
(build 35). We found that the purchase call relied on StoreKit to infer the
presenting window. We replaced it with StoreKit's SwiftUI scene-aware purchase
action so the confirmation sheet is presented from the active iPad window.

We also expanded the purchase controls to full-width hit targets and added
immediate progress plus visible results for success, cancellation, pending
approval, product unavailability, verification failure, and other StoreKit
errors. Product loading and purchase restoration now provide visible status as
well.

We verified the monthly and annual identifiers and tested the corrected flow on
an iPad Air 11-inch simulator with StoreKit test products, including purchase
presentation, cancellation, success, error messaging, and restore feedback.

To reach the purchase screen: complete the short household setup if prompted,
open the Parent area, unlock it when prompted, and open Kyndyn Premium. No
account sign-in is required.

The two subscriptions are included with this app-version submission and their
App Store Connect metadata is complete. Please review the updated build.

Thank you.
