# Notes on the Event GraphQL Response

## 1. Overall shape

The response is a JSON array with a single element, wrapping one event:

```json
[
  {
    "data": {
      "event": { "id": "39d20a52-...", "title": "ESN TUMi Semester Opening Party", ... }
    }
  }
]
```

Every object carries an Apollo-style `__typename`:

```json
{ "__typename": "TumiEvent" }
{ "__typename": "EventRegistration" }
{ "__typename": "User" }
{ "__typename": "Transaction" }
{ "__typename": "StripePayment" }
```

Money amounts and check-in times are strings, and timestamps are ISO-8601 UTC. The one exception is `additionalGuestPrice`, which is a number.

---

## 2. Event-level fields

```json
{
  "id": "39d20a52-8504-42d8-9706-0469ab7b3d2d",
  "title": "ESN TUMi Semester Opening Party",
  "icon": "party-popper:emoji",
  "start": "2026-04-09T20:00:00.000Z",
  "end": "2026-04-10T02:00:00.000Z",
  "participantLimit": 420,
  "participantRegistrationCount": 376,
  "totalRegisteredCount": 411,
  "participantsAttended": 183,
  "multiGuestSettings": {
    "enabled": true,
    "additionalGuestPrice": 10,
    "__typename": "EventMultiGuestSettings"
  },
  "costItems": [],
  "submissionItems": [],
  "createdBy": { "id": "c7ee803b-...", "fullName": "Lukas Pohl" },
  "organizerRegistrations": [ ... ],
  "participantRegistrations": [ ... ]
}
```

| Field | Notes |
|---|---|
| `participantLimit` | Capacity, 420 |
| `participantRegistrationCount` | 376, apparently the number of host registrations |
| `totalRegisteredCount` | 411, apparently hosts plus guests |
| `participantsAttended` | 183, apparently hosts who checked in (guests not counted) |
| `multiGuestSettings` | Turns the extra-guest feature on and sets the per-guest price |
| `costItems`, `submissionItems` | Empty for this event |

---

## 3. Two registration lists with different shapes

### 3.1 `organizerRegistrations`

This is a slim shape with no payment or guest data. `checkInTime` is always `null`.

```json
{
  "id": "e8e9ef47-f63c-4df2-91f7-af610dfb7767",
  "checkInTime": null,
  "__typename": "EventRegistration",
  "user": {
    "id": "49ff70f0-...",
    "fullName": "Justin Racu",
    "email": "iustinracu@gmail.com",
    "currentTenant": { "status": "FULL" }
  }
}
```

The same user can appear twice under different registration ids. Nikolo Rohrmoser (user `1bec6ade-...`) has registrations `352ff40e-...` and `6727f25a-...`.

### 3.2 `participantRegistrations`

This is the rich shape, with status, attendance, guest fields, transactions and submissions:

```json
{
  "id": "10db2d45-9ee9-49d3-b3ad-2111da5c14d6",
  "checkInTime": null,
  "status": "SUCCESSFUL",
  "didAttend": false,
  "guestCount": 0,
  "guestUnitPrice": null,
  "guestCheckIns": 0,
  "totalPartySize": 1,
  "remainingEntries": 1,
  "transactions": [ ... ],
  "submissions": [],
  "user": { "fullName": "Olivia Abbattista", ... }
}
```

### 3.3 Ordering of `participantRegistrations`

The list falls into two blocks:

1. **Not yet attended** (`didAttend: false`, `checkInTime: null`). It is sorted alphabetically by `lastName`, case-sensitive, so lowercase surnames come last. It starts with Abbattista and Abdullayev and ends with names like `cope` and `fjelkner`.
2. **Attended** (`didAttend: true`). It is sorted by `checkInTime` descending, from `2026-04-09T23:43:45Z` (Hannah Farrell) down to `2026-04-09T20:03:29Z` (Younghun Kim).

---

## 4. How additional guests are handled

Guests are not separate entities. They are not users or registrations, and they have no names or identities. A guest is only a counter on the host's registration.

### 4.1 The guest-related fields

| Field | Meaning |
|---|---|
| `guestCount` | Number of extra guests the host paid for |
| `guestUnitPrice` | `"10"` when guests exist, otherwise `null` |
| `totalPartySize` | `1 + guestCount` |
| `guestCheckIns` | Number of guests who have been checked in |
| `remainingEntries` | Entries still unused |

### 4.2 Example: no guests

```json
{
  "guestCount": 0,
  "guestUnitPrice": null,
  "guestCheckIns": 0,
  "totalPartySize": 1,
  "remainingEntries": 1
}
```

### 4.3 Example: one guest, not yet arrived (Bahram Abdullayev)

```json
{
  "didAttend": false,
  "guestCount": 1,
  "guestUnitPrice": "10",
  "guestCheckIns": 0,
  "totalPartySize": 2,
  "remainingEntries": 2
}
```

### 4.4 Example: one guest, host checked in, guest not (Hannah Farrell)

```json
{
  "checkInTime": "2026-04-09T23:43:45.795Z",
  "didAttend": true,
  "guestCount": 1,
  "guestUnitPrice": "10",
  "guestCheckIns": 0,
  "totalPartySize": 2,
  "remainingEntries": 1
}
```

### 4.5 Example: two guests, host and one guest checked in (Alexis Herrera Vegas)

```json
{
  "didAttend": true,
  "guestCount": 2,
  "guestUnitPrice": "10",
  "guestCheckIns": 1,
  "totalPartySize": 3,
  "remainingEntries": 1
}
```

### 4.6 Example: largest party (Arthur Vigand, 4 guests)

```json
{
  "didAttend": false,
  "guestCount": 4,
  "guestUnitPrice": "10",
  "guestCheckIns": 0,
  "totalPartySize": 5,
  "remainingEntries": 5
}
```

### 4.7 The `remainingEntries` formula

The values fit this formula:

```
remainingEntries = totalPartySize - (didAttend ? 1 : 0) - guestCheckIns
```

| Host attended | guestCount | guestCheckIns | totalPartySize | remainingEntries |
|---|---|---|---|---|
| no | 0 | 0 | 1 | 1 |
| no | 1 | 0 | 2 | 2 |
| yes | 0 | 0 | 1 | 0 |
| yes | 1 | 0 | 2 | 1 |
| yes | 2 | 1 | 3 | 1 |
| yes | 3 | 0 | 4 | 3 (Juan Salafranca) |

### 4.8 Observations

- Only two registrations have `guestCheckIns > 0`, Alexis Herrera Vegas and Stefano Sebbio, and both have exactly 1. Other attended hosts with guests, such as Hannah Farrell and Juan Salafranca, still have unused guest entries.
- `guestUnitPrice` is always `"10"`, matching `multiGuestSettings.additionalGuestPrice`. It does not follow the host's own ticket price, so a host who paid 8 with one guest pays 18.
- The response doesn't say which individual guest entered, only how many have.

---

## 5. Payments and guests

Every registration has exactly three transactions, all `CONFIRMED`, all linked to the same Stripe payment (`status: "succeeded"`).

### 5.1 Example: host only, no guests (Olivia Abbattista)

```json
"transactions": [
  {
    "id": "a56ef46f-...",
    "status": "CONFIRMED",
    "direction": "TUMI_TO_EXTERNAL",
    "amount": "0.35",
    "type": "STRIPE",
    "subject": "Application fees for ae1ea2b3-3984-4083-8579-3a0874fc6569",
    "stripePayment": { "id": "b54785c2-...", "status": "succeeded" }
  },
  {
    "id": "2dd9555f-...",
    "status": "CONFIRMED",
    "direction": "TUMI_TO_EXTERNAL",
    "amount": "0.37",
    "type": "STRIPE",
    "subject": "Stripe fees for ae1ea2b3-3984-4083-8579-3a0874fc6569",
    "stripePayment": { "id": "b54785c2-...", "status": "succeeded" }
  },
  {
    "id": "ae1ea2b3-3984-4083-8579-3a0874fc6569",
    "status": "CONFIRMED",
    "direction": "USER_TO_TUMI",
    "amount": "10",
    "type": "STRIPE",
    "subject": "Fee for: ESN TUMi Semester Opening Party",
    "stripePayment": { "id": "b54785c2-...", "status": "succeeded" }
  }
]
```

### 5.2 Example: host plus one guest (Bahram Abdullayev)

A single combined charge covers host and guest. The subject changes and the amount is 20 (10 + 1 × 10):

```json
{
  "id": "a743f94e-3f4e-495e-819a-311518a37804",
  "direction": "USER_TO_TUMI",
  "amount": "20",
  "subject": "Fee for: ESN TUMi Semester Opening Party,Additional Guests - ESN TUMi Semester Opening Party"
}
```

The fee rows scale with it (0.70 application fee, 0.49 Stripe fee).

### 5.3 Example: host plus four guests (Arthur Vigand)

```json
{
  "direction": "USER_TO_TUMI",
  "amount": "50",
  "subject": "Fee for: ESN TUMi Semester Opening Party,Additional Guests - ESN TUMi Semester Opening Party"
}
```

### 5.4 The three transaction rows

| Row | Direction | Subject pattern | Example |
|---|---|---|---|
| Main charge | `USER_TO_TUMI` | `Fee for: <Event>` (plus `,Additional Guests - <Event>` if guests) | `"amount": "10"` |
| Application fee | `TUMI_TO_EXTERNAL` | `Application fees for <main tx id>` | `"amount": "0.35"` |
| Stripe fee | `TUMI_TO_EXTERNAL` | `Stripe fees for <main tx id>` | `"amount": "0.37"` |

The fee rows point at the main charge only through the transaction id embedded in their subject string. There is no foreign-key field. All three rows share the same `stripePayment.id`.

### 5.5 Ticket price

The host's own ticket costs either 10 or 8. This is visible in the main charge for host-only registrations:

```json
{ "amount": "10", "subject": "Fee for: ESN TUMi Semester Opening Party" }
{ "amount": "8",  "subject": "Fee for: ESN TUMi Semester Opening Party" }
```

A discounted host with a guest pays 18 (Gautier Pauliat):

```json
{
  "amount": "18",
  "subject": "Fee for: ESN TUMi Semester Opening Party,Additional Guests - ESN TUMi Semester Opening Party"
}
```

---

## 6. Other fields

### 6.1 `submissions` and `submissionItems`

Both are empty arrays for every registration in this event:

```json
"submissions": []
```

### 6.2 `checkInTime` and `didAttend`

The two fields agree in this data. `didAttend` is `true` exactly when `checkInTime` is set.

```json
{ "checkInTime": null, "didAttend": false }
{ "checkInTime": "2026-04-09T23:34:06.391Z", "didAttend": true }
```

### 6.3 `status`

Every registration in `participantRegistrations` has `"status": "SUCCESSFUL"`.

---

## 7. Practical takeaways for working with this data

- Read guest totals from `guestCount` or `totalPartySize` on the host registration. Counting registrations misses them.
- Guests have no identity. To show or count them, use the counters on the host.
- To see who still has entries pending, filter on `remainingEntries > 0`.
- Per-guest payment detail does not exist. Host and guests share one charge.
- The response is easy to misread because the two registration lists differ in shape, so `organizerRegistrations` has no guest fields at all.
- The counts (`totalRegisteredCount` of 411 vs. `participantRegistrationCount` of 376) should be verified against the sum of `totalPartySize` before relying on them.
