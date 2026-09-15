# App Review follow-up — build 38 StoreKit presentation fix

Build 38 fixes the intermittent purchase-sheet failure found during the final
iPhone and iPad review pass. The app was changing observable paywall state at
the same moment StoreKit attempted to present Apple's confirmation sheet. That
could replace the presenting view and leave the screen stuck on “Contacting
Apple…” even though the products had loaded correctly.

The Premium screen now uses Apple's native `ProductView` for each already-loaded
subscription and does not mutate paywall state before StoreKit presents its
sheet. Kyndyn still processes StoreKit's completion result and refreshes verified
entitlements afterward.

The local StoreKit configuration matches the intended offer structure:

- Annual: two-week free trial, then $29.99 per year.
- Monthly: $3.99 per month, with no introductory trial.

The redundant close control above the plans was removed. Cancellation is shown
as a concise inline status, and restore remains available below the plans.

## Draft reply to App Review

Hello App Review,

We completed another iPhone and iPad purchase-flow audit and corrected an
intermittent StoreKit presentation race. In build 38, each subscription is
presented with Apple's native ProductView and the app no longer changes paywall
state while StoreKit is opening the confirmation sheet. This prevents the plans
from disappearing or remaining stuck on “Contacting Apple…”.

We also clarified the offers shown on the Premium screen: the annual plan has a
two-week free trial followed by $29.99 per year, while the monthly plan is $3.99
per month with no free trial. Restore Subscription remains available, and
verified App Store entitlements continue to determine Premium access.

To reach the screen, complete the short household setup if prompted, open
Parent, unlock it when prompted, and select Kyndyn Premium. No account sign-in
is required.

Thank you.
