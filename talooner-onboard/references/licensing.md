# Licensing

## Where to get a key

- Free 10-day demo: `https://talooner.dev/#pilot`
- Open source: `https://talooner.dev/#apply-open-source`
- Paid plans: `https://talooner.dev/pricing/`

The user copies the key from their license page. Never ask for the key value in
chat and never write it to the repository.

## Key format

`TLN1.<payload>.<signature>`

The payload is base64url JSON; the signature is Ed25519 over `TLN1.` plus the
payload. The documented placeholder above is safe to show. A real key is not.

## Local decode

`scripts/decode-license.sh` reads `TALOONER_LICENSE_KEY` or
`TALOONER_LICENSE_FILE` and prints only:

```
format=ok|bad|unknown
expired=yes|no|unknown
expires=YYYY-MM-DD|unknown
ai_review=yes|no|unknown
```

It never prints the key, email or plan.

Exit contract:

- `0` when the key was parsed, even when `expired=yes` or `ai_review=no`.
- `2` when the key is missing, malformed, unreadable, or the decoder is not
  available.

The skill decides what to do with the answer. A malformed or unknown result
stops. Expired or no-AI sends the user to their license page for the current key.

## The decode is a hint

`exp` and `features` are signed into the key. An old key still says expired after
a renewal, and a revoked key still decodes as valid. The online license check on
the first CI run is authoritative.

If the local decode says expired or no-AI, ask for the current key from the
license page before concluding anything. Never treat a local `valid` as proof that
the license is active.

## AI review

The key must include the `ai_review` feature. Without it, AI review does not run,
even when a model key is present. A decision model also needs `ai_review` because
it is part of the review path.

## What leaves the repository

- License check: the key, a nonce and the version. No code.
- Telemetry: a run summary. No code, diffs or comment text.
- Forge API: the calls needed to read the PR and write the check and comment.
- The user's own model provider: only where a rule asks for a model call, with
  the user's key.

The user's coding agent may read code locally with consent. That analysis goes to
the agent and its model, not to Talooner.
