# Check-In Mutation: `useRegistrationEntry` and Guest Check-In Hypothesis

## 1. The observed call

### Request

```json
{
  "operationName": "useRegistrationEntry",
  "variables": {
    "registrationId": "6bb6d9e9-a291-49d6-8e78-625bc2d49b0d",
    "manual": false
  },
  "query": "mutation useRegistrationEntry($registrationId: ID!, $manual: Boolean) {
    useRegistrationEntry(registrationId: $registrationId, manual: $manual) {
      id guestCount guestCheckIns checkInTime totalPartySize remainingEntries
      usageLog { timestamp actorId manual note __typename }
      __typename
    }
  }"
}
```

### Response (host only, no guests)

```json
{
  "data": {
    "useRegistrationEntry": {
      "id": "6bb6d9e9-a291-49d6-8e78-625bc2d49b0d",
      "guestCount": 0,
      "guestCheckIns": 0,
      "checkInTime": "2026-08-29T11:16:12.923Z",
      "totalPartySize": 1,
      "remainingEntries": 0,
      "usageLog": [
        {
          "timestamp": "2026-08-29T11:16:12.923Z",
          "actorId": "2bba0179-b89a-462e-be57-8b9f1b4819f8",
          "manual": false,
          "note": null,
          "__typename": "RegistrationUsageEntry"
        }
      ],
      "__typename": "EventRegistration"
    }
  }
}
```

## 2. Key observations

1. **The mutation takes only a `registrationId`.** There is no guest identifier and no argument like `isGuest` or `guestIndex`. Guests have no identity in the data model (see the first notes file), so this fits.
2. **The name is `useRegistrationEntry`, not "checkIn".** It treats a registration as holding a pool of entries, and each call consumes one.
3. **`manual` is a flag on the call.** `false` here, so this was a normal scan. It probably means `true` when an organizer checks someone in by hand, for example by searching their name instead of scanning a QR code.
4. **`usageLog` is a new field.** It is an append-only list, one `RegistrationUsageEntry` per call, with `timestamp`, `actorId` (the organizer who performed the check-in), `manual`, and a free-text `note`.
5. **`remainingEntries` is 0 after one call** for a party of 1 (`totalPartySize: 1`).
6. **`checkInTime` equals the first log entry's timestamp** (`11:16:12.923Z` in both).

## 3. Hypothesis

**Guests are checked in by calling the same mutation again on the host's registration id.** Nothing distinguishes host from guest in the call. The backend decides which counter to update based on the registration's current state.

### Proposed server logic

```text
useRegistrationEntry(registrationId, manual):
    reg = load registration

    if reg.remainingEntries <= 0:
        error "no entries left"

    append { timestamp: now, actorId: currentUser, manual, note } to reg.usageLog

    if reg.checkInTime is null:        # first scan = the host
        reg.checkInTime = now
        reg.didAttend = true
    else:                              # every later scan = one guest
        reg.guestCheckIns += 1

    reg.remainingEntries = reg.totalPartySize - reg.usageLog.length
    return reg
```

### How it plays out for a party of 3 (host + 2 guests)

| Scan | `checkInTime` | `didAttend` | `guestCheckIns` | `remainingEntries` | `usageLog` length |
|---|---|---|---|---|---|
| Before | `null` | `false` | 0 | 3 | 0 |
| 1st (host) | set | `true` | 0 | 2 | 1 |
| 2nd (guest) | unchanged | `true` | 1 | 1 | 2 |
| 3rd (guest) | unchanged | `true` | 2 | 0 | 3 |
| 4th | | | | | rejected |

### Why this matches the earlier event data

The registration data shows states that all fit this model.

**Host attended, guest not yet (Hannah Farrell):** one scan used, one entry left.

```json
{ "didAttend": true, "guestCount": 1, "guestCheckIns": 0, "totalPartySize": 2, "remainingEntries": 1 }
```

**Host plus one of two guests (Alexis Herrera Vegas):** two scans used, one entry left.

```json
{ "didAttend": true, "guestCount": 2, "guestCheckIns": 1, "totalPartySize": 3, "remainingEntries": 1 }
```

**Nothing scanned yet (Bahram Abdullayev):**

```json
{ "didAttend": false, "guestCount": 1, "guestCheckIns": 0, "totalPartySize": 2, "remainingEntries": 2 }
```

**Host only, fully used (the response above):**

```json
{ "guestCount": 0, "guestCheckIns": 0, "totalPartySize": 1, "remainingEntries": 0 }
```

All of these obey:

```
remainingEntries = totalPartySize - (didAttend ? 1 : 0) - guestCheckIns
```

which equals `totalPartySize - usageLog.length` if the log has one entry per scan.

## 4. Practical picture at the door

1. The host shows their registration QR code, which probably encodes the `registrationId`.
2. The organizer scans it, and the app calls `useRegistrationEntry(registrationId, manual: false)`.
3. The response includes `remainingEntries`. If it is above 0, the app can show something like "2 more guests can enter".
4. Guests then show the same QR code, or the host holds it up again, and each scan uses one more entry.
5. If a QR code isn't available, an organizer finds the registration by search and calls the mutation with `manual: true`. The `note` field probably records why.

## 5. Alternative hypotheses

- **A separate mutation for guests.** This is unlikely, because `guestCheckIns` and `remainingEntries` are returned from this same mutation, and the call has no guest argument.
- **Guests scanned before the host.** Under the proposed logic, the first scan always counts as the host, even if a guest arrives first. The data can't distinguish this, but the counters only work if the host is treated as first.
- **The host must be checked in before guests.** The server might refuse a second scan until `checkInTime` is set. This is indistinguishable from the model above unless the API is tested.

## 6. How to verify

1. Use a registration with `guestCount >= 1` and call the mutation repeatedly. Watch which fields change on each call.
2. Confirm that the first call sets `checkInTime` and `didAttend`, and that later calls only increment `guestCheckIns`.
3. Confirm that `usageLog.length` equals `totalPartySize - remainingEntries`.
4. Call it once more when `remainingEntries` is 0 and see the error message.
5. Call with `manual: true` and check how the log entry differs. Also check whether `note` can be passed, since the mutation as captured has no `note` argument, so it may be set elsewhere.
6. Re-fetch the registration through the earlier event query and check that `guestCheckIns` and `didAttend` reflect the scans.

## 7. Open questions

- Is `checkInTime` ever updated on later scans, or does it stay at the first scan? The single-entry response can't show this.
- Does the mutation reject a repeated scan when `remainingEntries` is 0, and with what error?
- How is `note` populated? It has no argument in the captured call.
- Is `actorId` always the organizer's user id? In the example it is `2bba0179-...`, which doesn't match the registration id, so it is likely the scanner's user.
