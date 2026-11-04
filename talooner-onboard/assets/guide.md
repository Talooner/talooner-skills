# billing guide

`billing/` owns prices, invoices and refunds. This guide is read at review
time, one rule at a time.

## Amounts

### Amounts are decimal strings, never floats

Money crosses this boundary as a string with two decimals.

Applies to: `billing/`.

> **Gotcha**: `float64` cents drift after a few thousand invoices.

### An invoice total is never negative

A credit note is a separate record, not a negative invoice.

## Refunds

### Refunds carry an idempotency key

Every refund call includes the caller's key, and a repeat with the same key
returns the first result instead of charging twice.

## Specs

### billing/refund.go

- Rejects a refund with no idempotency key.
- Returns the first refund for a repeated key.

### billing/invoice_test.go

- Covers a zero-amount invoice.
- Covers rounding at half a cent.

## Advice

Keep tax maths in small pure helpers, not inside the request handler.
