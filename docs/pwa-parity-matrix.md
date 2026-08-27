# PWA parity matrix

| Capability | Native plan | Notes |
|---|---|---|
| Profile selection and roles | Native v1 core | Native identity gateway and protected Parent area implemented |
| Family/personal dashboards | Native v1 core | Implemented locally |
| Individual/shared quests | Native v1 core | Participant event records |
| One-time and weekly recurrence | Native v1 core | Implemented rule foundation |
| Due/overdue and late XP | Native v1 core | Deterministic household-time rules |
| Completion history and undo | Native v1 core | Append-friendly reversal |
| XP, levels, streaks, badges | Native v1 core | Implemented with durable recognition and collection milestones |
| Family reward goal | Native v1 core | Implemented projection |
| Parent people/quest editing | Native v1 core | Create/edit/archive/restore and integrity rules implemented |
| Local notifications | Native v1 core | Device profile, quiet hours, privacy, permission, and local scheduling implemented |
| Companion identity | Native v1 core | Starter artwork copied with provenance |
| CloudKit household sharing | Native v1.1 | Protocol boundary now; production container later |
| StoreKit family subscription | Builds 32–33 | Pricing and entitlement rules defined; StoreKit implementation next |
| Broadcasts | Native v1.1 | Model boundary included |
| Full collections/backgrounds | Native v1.1 | Architecture supports them |
| PWA JSON migration | Native v1.1 | Versioned dry-run design and fixtures |
| Calendar read-only feeds | Builds 14/18 | Optional EventKit calendars; read-only, device-local, and refined on Home |
| Weather | Builds 14/18 | Apple WeatherKit derived cache; device-local and never shared source truth |
| kyndyn assistant | Later | Privacy and parent-control review required |
| Web push/VAPID | Intentionally replaced | Native local/remote notification stack |
| Flask/Jinja JSON datastore | Intentionally replaced | SwiftUI + SwiftData + CloudKit |
| Family access password | Intentionally replaced | Native household invitation/account model |
| Legacy claim-once mode | Intentionally omitted | Migration normalizes to an explicit supported mode |
