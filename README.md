# Turnstile Check-in

A resilient Flutter application for event ticket validation and check-in via QR code scanning. Built for high-volume entry turnstiles with offline persistence, background check-in queuing, automatic retry management, and GraphQL integration.

---

## System Overview & Architecture

```
                                  [ QR Code (UUID) ]
                                          |
                                          v
                              +-----------------------+
                              |   AI Barcode Scanner  |
                              +-----------------------+
                                          |
                                          v
                             +-------------------------+
                             | UUID Format Validation  |
                             +-------------------------+
                                          |
                    [Valid UUID]          |          [Invalid]
            +-----------------------------+-----------------------------+
            |                                                           |
            v                                                           v
+-------------------------+                                 +-----------------------+
|  GraphQL Registration   |                                 | Inline Error Feedback |
|  Query (getRegistration)|                                 | (Haptic / Toast)      |
+-------------------------+                                 +-----------------------+
            |
            v
+-------------------------+
| Ticket Preview Card     |
| - Attendee Details      |
| - Event Matching Check  |
| - Attendance Warning    |
+-------------------------+
            |
    [User Taps "Check In"]
            |
            v
+-------------------------+       [Immediate Scanner Reset]
| Enqueue Check-In Item   | -------------------------------------> (Ready for next attendee)
+-------------------------+
            |
            v
+-----------------------------------------------------------+
|               Background Check-In Queue                   |
|  - FIFO execution with async worker                       |
|  - Up to 3 automatic retries on failure                   |
|  - Escalates to Manual Retry if 3 attempts fail           |
|  - Safe Mode / Live Mode execution guard                  |
|  - Persistent storage across app restarts                 |
+-----------------------------------------------------------+
            |
            +------------------------------------+
            | (On Success)                       | (After 3 Failures)
            v                                    v
+-------------------------+          +-------------------------+
| Checked-In History      |          | Manual Retry Queue View |
| (Persistent Database)   |          | (User action required)  |
+-------------------------+          +-------------------------+
```

---

## Key Features & Approaches

### 1. Camera Scanning & UUID Validation
- **Package**: `ai_barcode_scanner` (powered by `mobile_scanner`).
- **Format Verification**: Every scanned QR payload is checked with a strict UUID format regex before making any network calls.
- **Scan Debounce**: Prevents accidental repeated trigger of the same code in rapid succession.
- **Manual Input Fallback**: Allows entering or pasting a UUID string manually for scratched or unreadable QR codes.

### 2. GraphQL Operations & Flexible Parsing
- **Ticket Lookup Query**:
  ```graphql
  query getRegistration($id: ID!) {
    registration(id: $id) {
      id
      transactions { id status direction amount type subject stripePayment { id status } }
      status
      type
      didAttend
      checkInTime
      guestCount
      guestUnitPrice
      guestCheckIns
      totalPartySize
      remainingEntries
      usageLog { timestamp actorId manual note }
      event { id title icon }
      user { id fullName picture esnCardNumber esnCardValidUntil }
    }
  }
  ```
- **Flexible Schema Tolerant Parser**: Safely handles unknown or newly added fields, missing properties, or unexpected responses.
- **High Timeout & Resilient Networking**: Configurable HTTP timeout (default 30 seconds) designed for congested event Wi-Fi and cellular connections.

### 3. Background Check-In Queue (Decoupled Flow)
- **Zero-Block Scanning**: Scanning the QR code **does not automatically check in**. The user inspects attendee credentials and taps the **Check In** button.
- **Immediate Return**: Enqueueing a check-in instantly returns the scanner to ready state so the next attendee can be scanned without waiting for the network response.
- **3x Auto-Retry**: If an enqueued check-in fails (e.g., due to timeout or network dropout), it retries automatically up to 3 times with exponential backoff.
- **Manual Retry State**: If all 3 attempts fail, the item transitions to `needs_manual_retry` and can be inspected and retried from the Queue screen.

### 4. Safety Guard (Safe / Dry-Run Mode)
- Prevents unintended check-in mutations against the live database during testing or configuration.
- Safe Mode simulates the check-in mutation locally and verifies the queue pipeline without hitting the production backend.
- Live mode can only be enabled explicitly with valid credentials.

### 5. Multi-Event Support
- Multiple Event IDs can be registered in the Settings view.
- When scanning, the app checks if `registration.event.id` matches one of the active event IDs.
- Tickets for non-active events trigger a clear warning to alert door staff.

### 6. Strict Offline Security Policy
- **No Arbitrary Offline Check-Ins**: Unknown UUIDs cannot be checked in while offline under any circumstance.
- **Downloaded Roster Requirement**: Offline ticket resolution and admission is strictly permitted only if the ticket is present in the locally downloaded attendee list retrieved from the server prior to going offline.
- **Anti-Fraud Guard**: If a ticket is not in the cached roster and the live server is unreachable, the app presents a blocking **"Cannot Verify Offline"** error to prevent fraudulent admissions with arbitrary QR codes.
- **Immediate Resolution & Background Sync**: For tickets present in the downloaded roster, check-in is immediate; entry deductions are saved to the persistent local database and enqueued for background synchronization once connectivity is restored.

### 7. Continuous Scanning & Camera Lifecycle
- **Continuous Scan Engine**: The scanner runs in continuous mode with a 250ms debounce window, eliminating single-scan lockups.
- **Battery-Saving Frame Freeze**: When a ticket is detected or being inspected, ML frame detection is paused (`pauseScanning()`) rather than halting the native camera hardware, avoiding CameraX texture desynchronization while minimizing CPU and battery consumption.
- **Scrim Overlay**: When the inspection sheet opens, a semi-transparent scrim overlay fades in over the camera viewfinder to guide operator focus.

### 8. Persistence & Storage
- **App Configuration**: Managed via `shared_preferences` (Bearer Token, API URL, Timeout, Active Event IDs, Safe Mode).
- **Downloaded Event Roster**: Cached locally to power offline ticket verification and entry tracking.
- **Queue State**: Persisted across app restarts so pending or failed check-ins are never lost.
- **Checked-In Attendees List**: Persisted locally in JSON format to track all attendees admitted through the turnstile.

---

## Configuration & Environment (`.env`)

The app communicates with the backend via GraphQL.

To configure your target GraphQL endpoint without committing sensitive URLs:

1. Copy the example configuration to `.env`:
   ```bash
   cp .env.example .env
   ```
2. Set your `GRAPHQL_ENDPOINT` in `.env`:
   ```env
   GRAPHQL_ENDPOINT=https://your-platform.example.com/graphql
   ```
3. Run or build the app with `--dart-define-from-file`:
   ```bash
   # Development
   flutter run --dart-define-from-file=.env

   # Web Build
   flutter build web --dart-define-from-file=.env
   ```

### IDE Setup (Android Studio / VS Code)

- **Android Studio / IntelliJ**:
  Go to **Run > Edit Configurations...** $\rightarrow$ select your Flutter configuration (e.g. `main.dart`) $\rightarrow$ in **Additional run args**, enter:
  ```text
  --dart-define-from-file=.env
  ```
  *(A preconfigured `.idea/runConfigurations/main_dart.xml` has already been set up with this argument).*

- **VS Code**:
  In `.vscode/launch.json`, add `"args": ["--dart-define-from-file=.env"]` to your configuration.

*Note: You can also adjust or override the API URL at any time directly in the app's **Settings** screen.*

---

## Project Structure

```
lib/
├── main.dart                   # Application entrypoint, M3 theme, 3-tab navigation
├── models/
│   ├── registration.dart       # EventRegistration, EventDetails, User, Transactions models
│   ├── queue_item.dart         # Check-in queue item & retry status models
│   └── app_settings.dart       # Settings, Bearer auth, Event IDs model
├── services/
│   ├── graphql_service.dart    # GraphQL HTTP queries and mutations
│   ├── storage_service.dart    # Local persistence (cache, queue, attendees)
│   └── queue_service.dart      # Background queue worker, auto-retry logic
├── providers/
│   ├── scanner_provider.dart   # Camera scan state, validation, ticket preview
│   ├── attendees_provider.dart # Checked-in list, search filter, roster caching
│   └── settings_provider.dart  # Settings management & safe-mode toggle
├── screens/
│   ├── scanner_screen.dart     # QR Scanner with camera controls, scrim overlay & preview sheet
│   ├── attendees_screen.dart   # Merged Attendees list & Sync Queue tabs with M3 TabBar
│   ├── queue_screen.dart       # Embedded Check-in queue view & manual retry controls
│   ├── settings_screen.dart    # Token, API URL, Event IDs, timeout configuration
│   └── web_auth_screen.dart    # Web login session capture & bookmarklet assistant
└── widgets/
    ├── admission_dialogs.dart  # Unpaid / group admission confirmation dialogs
    ├── m3_shimmer.dart         # Shimmer gradient animation widget
    ├── m3_swipe_lock.dart      # Swipe-to-confirm slider
    └── ticket_preview_sheet.dart # Slide-up ticket details and check-in sheet
```

---

## Disclaimer

This project was developed with the assistance of generative AI.

