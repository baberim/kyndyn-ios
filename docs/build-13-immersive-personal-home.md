# Build 13 immersive personal Home

Build 13 makes earned profile art part of Home's identity instead of presenting
it as a separate preview card.

## Home composition

- The selected background fills a responsive Home header.
- The selected companion is composed into that scene as foreground artwork.
- The person's greeting and rotating encouragement are rendered inside the
  scene with contrast gradients and shadows for legibility.
- Family announcements follow the personal header, so communication remains
  prominent without displacing the active person's identity.
- The former Home profile shortcut was removed because the same customization
  is now clearly available from Settings.

The header adapts its height and artwork balance for compact and regular width
layouts. Accessibility Dynamic Type receives additional height, more text
width, and a smaller companion treatment to reduce collisions. The combined
scene has a single VoiceOver description naming the person, message,
background, and companion.

## Data and privacy

This is a presentation-only milestone. It does not change unlock rules,
progression, CloudKit ownership, or profile synchronization. Background and
companion selections continue to use the existing synced Person fields, while
app icon selection remains device-local.

No new personal information, analytics, credentials, or hosted services are
introduced.
