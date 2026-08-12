# Calendar and weather (Build 14)

Build 14 adds two optional, device-local views of the family’s day.

## Calendar

- kyndyn requests full calendar read access because EventKit does not offer a read-only permission tier.
- The app performs no calendar writes and exposes no create, edit, or delete operation.
- A person chooses individual device calendars in Settings > Calendar.
- Home reads upcoming events directly from EventKit. Event titles and calendar identifiers are not copied into SwiftData, CloudKit, family backups, sync logs, or notifications.
- Revoking permission leaves the family loop working normally and simply removes calendar content from Home.

## Weather

- kyndyn requests When In Use location permission only after weather is enabled in Settings.
- Coordinates are passed directly to Apple WeatherKit and are never persisted by kyndyn.
- A small derived summary (temperature, high, low, condition, symbol, and fetch time) is cached in local device settings for up to 30 minutes.
- The cache is excluded from CloudKit and household backups and is deleted when weather is disabled.
- A cached summary can remain visible during a temporary network or WeatherKit failure. kyndyn does not promise continuous or background weather updates.

## Apple configuration

Calendar requires no developer-portal service beyond the included privacy usage description. Weather requires the WeatherKit capability for the `com.kyndynfamily.kyndyn` App ID and a regenerated provisioning profile. The checked-in entitlement contains no Team ID, credentials, or private data.

Before physical or TestFlight validation:

1. In Certificates, Identifiers & Profiles, open the `com.kyndynfamily.kyndyn` identifier and enable WeatherKit.
2. In Xcode, select the kyndyn target and confirm WeatherKit appears under Signing & Capabilities.
3. Allow automatic signing to refresh the development/distribution provisioning profiles.
4. Test with fictional calendar entries and confirm Production CloudKit remains untouched; WeatherKit is separate from the CloudKit schema.

## Limitations

Apple controls calendar/location permission prompts and WeatherKit availability. Simulator location must be supplied through Xcode. Weather and calendar refresh when the app is used; neither is advertised as real-time or guaranteed background data.
