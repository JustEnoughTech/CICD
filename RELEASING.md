# Release channels

Three kinds of tag, three different promises. Consumers pick a channel; the channel decides how
much change they absorb and how fast.

| Tag | Moves? | Promise | Who should pin here |
|---|---|---|---|
| `vX.Y` | **never** | Exactly this commit, forever. | Anyone who needs a build to be reproducible next year. |
| `latest` | every release | Newest release. Tested in CI, **not** validated in the fleet. | This repo's own self-tests; early adopters who want fixes immediately and accept churn. |
| `lts` | only after confirmation | The release that has been **run and confirmed** in the fleet. | **The GT application repos.** Production security gates should change deliberately, not on merge. |

## The promotion path

```
merge to main  →  vX.Y (immutable)  →  latest  →  [ CONFIRMATION ]  →  lts
```

`latest` moves as part of the merge. **`lts` moves only when the confirmation below has actually
happened** — not when someone believes it has.

## What "confirmation" means — this is the load-bearing part

A tag that moves on someone's judgement is not a channel, it is a rumour. `lts` advances only when
all of the following are true, and the promoting commit message says which release it promoted and
what evidence it relied on:

1. The release has been `latest` for at least one full working day.
2. Every lane has run **green** on at least **two** consuming repositories — not just this repo's
   own fixtures.
3. No lane has been observed failing for a reason unrelated to the code under test (a flaky or
   environment-dependent lane is not yet LTS-grade).
4. Any lane added or changed in the release has been observed going **RED on a real finding** and
   then GREEN. A lane never seen failing is not a gate, and must not be promoted as one.

If a criterion cannot be met, `lts` does not move. Staying behind is a valid state; it is what the
channel is for.

## Current state

- `v1.1` = `50240cac` — immutable.
- `latest` = `50240cac`.
- **`lts` does not exist yet, deliberately.** Nothing has been confirmed: the self-hosted runner is
  not registered, and no consuming repository has run these lanes even once. Minting `lts` now would
  assert a validation that has not happened, which is precisely the failure this project exists to
  avoid. The first `lts` is cut after the first green run across two consuming repos.
- `v1` currently also points at `50240cac`. It predates this policy and now duplicates `latest`.
  **Decide:** keep it as a major-series alias, or retire it so there are exactly two moving tags.
  Three moving tags with overlapping meanings is how a consumer ends up pinned to something nobody
  can describe.

## Caller guidance

- GT application repos: `@lts` once it exists; `@v1.1` until then. **Not** `@latest`.
- This repo's self-tests and any deliberate early adopter: `@latest`.
- Reproducing an old build: the exact `@vX.Y`.

A moving tag means a consumer's security gates can change without a PR in their repo. That is the
point of `lts` — the change is deliberate and confirmed, rather than automatic.
