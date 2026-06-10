# Langclaw AI Celo GitHub Profile Repository

This repository owns the public GitHub organization profile for
`Langclaw-AI-Celo`. The rendered profile lives at
[`profile/README.md`](profile/README.md) and should stay aligned with the
backend, frontend, and contracts folder docs.

This local checkout is a single git root with `.github`, `backend`,
`contracts`, and `frontend` tracked as folders. Keep the public profile links
pointed at the `Langclaw-AI-Celo` repositories, but run local status and diff
checks from the workspace root when preparing atomic commits.

Current public app entrypoint:

```text
https://langclawcelo.vercel.app
```

## Source Of Truth

| Area | Source |
| --- | --- |
| Public product positioning | `profile/README.md` |
| Backend runtime and API | `../backend/README.md`, `../backend/docs/API_REFERENCE.md` |
| Celo eligibility and proof status | `../backend/docs/CELO_ELIGIBILITY.md` |
| Campaign progress snapshots | `../backend/docs/CAMPAIGN_PROGRESS_*.md` |
| Smart contract addresses and interfaces | `../contracts/README.md` |
| Frontend user flows | `../frontend/README.md` |

## Profile Maintenance Rules

- Keep the public copy Celo-first. Mantle is supported by the codebase as an
  optional legacy or explicit-analysis chain, but this organization profile is
  for the Celo submission.
- Do not claim live-funds trading. Langclaw is analysis-first; Strategy Lab
  records backtests and paper-trade proofs only.
- Keep Celo addresses, agent IDs, proof transactions, and MiniPay/USDT wording
  synchronized with the backend and contracts docs.
- Keep the public app URL synchronized with frontend config and deployment.
- Prefer concrete repo links and live proof facts over marketing-only wording.
- When Celo eligibility changes, update this repo together with the backend
  docs and contracts README in the same pass.

## Current Public Claims

- Product chain: Celo mainnet `42220`.
- Default usage-credit asset: Celo USDT.
- Agent identity: ERC-8004 agent ID `9109` plus Self Agent ID `133`.
- Registration transactions: ERC-8004
  `0x1b7cb74378db42551a3cbc81dcd560f337df1593d4ef1cd70ee44ff269bdc7f3`
  and Self Agent ID
  `0x3c7d0cc69f77d2aef5ab21bfe703d0f33f7037d5e2162209d78b23b5c3f1cde6`.
- Proof contracts: `LangclawRegistry`, `LangclawTradingJournal`, and
  `LangclawUsageVault` are deployed on Celo.
- Latest documented Celo decision proof: decision `#38`,
  signal `campaign-backend-proof`, tx
  `0x4485061e6e6151bc51c106f025b7d062468121595ca5cb4198f7307ea5ec5f06`.
- Latest documented proof run:
  `github-backend-650d33c-2026-06-06`, evidence
  `https://github.com/Langclaw-AI-Celo/backend/commit/650d33c80a2a54c5a706c79722a6eeeaa5dd4fd8`.
- Latest documented Self-linked Celo decision proof: decision `#1`, signal
  `smart-money`, tx
  `0x2a2f94c40e2b5c080bd330f43f3ce6bc6b05e054b6626ce3ab2716220f0d3211`.
- The 2026-06-07 backend proof-readiness pass reports `npm run
  check:celo-proof` now returns `ready` because the default proof path prefers
  the ERC-8004 campaign agent `9109`.
- Self Agent ID `133` remains part of the public proof story for linked-proof
  and human-verification flows, not as the default campaign proof writer.

## Current Proof Layer Identifiers

| Item | Value |
| --- | --- |
| `LangclawRegistry` | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` |
| `LangclawTradingJournal` | `0x69984c20176704685236fd633192d7de1c13a5ec` |
| `LangclawUsageVault` | `0x837a2948586de4e7638c742f99e520ffc049bcf7` |
| Celo USDT deposit token | `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e` |
| ERC-8004 identity registry | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| Agent owner / recorder | `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c` |

## Update Checklist

1. Check the current Celo status from `backend/`:

   ```bash
   npm run check:eligibility
   npm run check:celo-proof
   ```

2. Confirm the profile still matches the folder READMEs:

   ```bash
   git status --short .github backend contracts frontend
   ```

3. Capture the current short head before refreshing any public campaign
   snapshot from this single-root checkout:

   ```bash
   git rev-parse --short HEAD
   ```

4. Keep links pointed at the public `Langclaw-AI-Celo` repositories.
