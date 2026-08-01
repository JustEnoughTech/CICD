# Vendored SAST rules

Rules for the `security / sast` opengrep lane. **Vendored, not fetched.** `opengrep scan
--config <dir>` is pointed at this directory; nothing is downloaded from a rule registry at
scan time.

## Why vendored

Two independent reasons:

1. **Licensing.** The opengrep *engine* is LGPL-2.1 and free. Its usual rule source is not.
   `--config p/ci` resolves to `https://semgrep.dev/<id>` — Semgrep Inc.'s registry, under the
   proprietary **Semgrep Rules License v1.0** (*"You may use the rules only for your own internal
   business purposes. This license does not allow you to distribute the rules."*). Not
   OSI-approved. `semgrep/semgrep-rules` carries that same licence — the repo and the registry
   are **not** differently licensed, and it was never plain LGPL-2.1 (before the 2024-12-13
   relicense it was LGPL-2.1 **+ Commons Clause**). This repo is public, so vendoring that
   content here would be distribution.
2. **Air-gap.** A network fetch at scan time cannot work in the air-gapped delivery flavour, and
   makes every CI run depend on a third party's uptime and terms.

Everything below is **MIT**, which permits redistribution provided the copyright notice and
licence text travel with the copy. Each source directory therefore keeps its upstream `LICENSE`
file. **Do not delete them** — that is the condition on which we may ship these at all.

## Sources

Licence verified by reading each upstream `LICENSE` file directly, not the GitHub sidebar label.
That distinction matters: GitLab's `sast-rules` advertises MIT at the root while the tree
contains a proprietary GitLab-EE bucket and ~100 Commons-Clause rules. It is excluded for
exactly that reason.

| Directory | Upstream | SPDX | Commit vendored | Verified | Rules |
|---|---|---|---|---|---|
| `apiiro/` | [apiiro/malicious-code-ruleset](https://github.com/apiiro/malicious-code-ruleset) | MIT | `a21246b666f34db899f0e33add7237ed70fab790` | 2026-08-01 | 101 |
| `elttam/` | [elttam/semgrep-rules](https://github.com/elttam/semgrep-rules) | MIT | `f34f52accdf56c1ace669c137a413b4aac25fe71` | 2026-08-01 | 29 |
| `0xdea/` | [0xdea/semgrep-rules](https://github.com/0xdea/semgrep-rules) | MIT | `fcbd4759de19e14b6d1e139a13502bbba816ecf2` | 2026-08-01 | 50 |
| `dgryski-semgrep-go/` | [dgryski/semgrep-go](https://github.com/dgryski/semgrep-go) | MIT | `db0227c03f4b3c4e71d900188d51db4c81d66932` | 2026-08-01 | 66 |

**246 rules total** — 123 `ERROR`, 96 `WARNING`, 27 `INFO`. The lane gates at `ERROR` by
default, so **123 rules can currently fail a build**; the rest are reported in the artifact only.

Language spread (rules may declare several): go 76, cpp 49, c 48, java 27, python 18,
javascript 14, typescript 14, lua 12, php 12, ruby 12, clojure 11, csharp 11.

### Recording the SHA is the point

Our copy stays under the licence in force **at the moment of copying**, which for MIT is
irrevocable. Pinning the exact commit means a future upstream relicense is *detectable* rather
than silent: re-verify against the recorded SHA before pulling anything new. This is not
bookkeeping — a confident, precise, wrong licence claim is what put this lane on hold in the
first place.

## Curation decisions

- **elttam: `rules/` only, not `rules-audit/`.** Upstream's own README splits them — `rules/` are
  "generally vulnerabilities", `rules-audit/` exists "to augment manual source code review". Every
  audit rule is INFO or WARNING, so none could ever fire an `ERROR` gate; including them would add
  78 rules of artifact noise and zero gating power.
- **elttam's `LICENSE` reads `Copyright (c) 2020 Semgrep`.** Recorded because it looks alarming and
  someone will eventually notice it. Checked: the repo is **not** a fork (no upstream parent),
  created 2022, rules are original elttam work (`net-url-pointer-alias-mutation`,
  `gorilla-cookiestore-default-samesite-none`), and no rule carries registry provenance metadata.
  The attribution line is a stale MIT-template artifact; the MIT grant itself is unambiguous.
- **apiiro is a malicious-code/obfuscation ruleset**, not a classic vulnerability set. It is aimed
  at supply-chain implants (dynamic execution, obfuscation). Expect it to be the noisiest source
  against legitimate code that legitimately uses `eval`, minification, or codegen.

## Updating

1. Re-read the upstream `LICENSE` **file** and confirm it still grants MIT.
2. Copy the rule files; keep the upstream `LICENSE` alongside them.
3. Update the SHA, the verified date, and the rule counts in the table above.
4. Run the lane against a known-vulnerable fixture and confirm it still goes **red**, then against
   clean code and confirm **green**. A rule set that cannot be observed failing is not a gate.

## What this is not

This is a deliberate, auditable ~246-rule subset with a known licence position. It is **not**
parity with the Semgrep registry (thousands of rules), and it is not uniform across languages —
Go, C/C++ and malicious-code patterns are well covered; Python, JS/TS and C# are thin, and
`security / sast` leans on bandit and njsscan for Python and Node. Buying registry breadth is a
licensing decision to be made consciously, not a gap to close by quietly re-adding `p/ci`.
