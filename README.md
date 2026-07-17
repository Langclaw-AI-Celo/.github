# Langclaw AI Celo GitHub Profile Repository

This repository owns the public GitHub organization profile for
`Langclaw-AI-Celo`. The rendered profile lives at
[`profile/README.md`](profile/README.md) and should stay aligned with the
backend, frontend, and contracts folder docs.

This workspace keeps the public GitHub profile in the separate `org-profile`
repository beside the `backend`, `contracts`, and `frontend` repositories.
The shared parent directory is not a Git repository. Each child repository is
a single git root. Keep public links pointed at `Langclaw-AI-Celo`, and run
status or diff checks inside each repository.

Current public app entrypoint:

```text
https://langclawcelo.vercel.app
```

Current public repository links:

- Frontend: `https://github.com/Langclaw-AI-Celo/frontend`
- Backend: `https://github.com/Langclaw-AI-Celo/backend`
- Contracts: `https://github.com/Langclaw-AI-Celo/contracts`

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
- Latest documented Celo decision proof: decision `#47`,
  signal `campaign-backend-proof`, tx
  `0xb50e7bd12af0cbca9a6246a80f1976da753d359fbd1553458712b43aa40681b1`.
- Latest documented proof run:
  `github-backend-433b125-2026-06-08`, evidence
  `https://github.com/Langclaw-AI-Celo/backend/commit/433b12562c6472dae9e3ff5a1286596a0420eaeb`.
- Latest documented Self-linked Celo decision proof: decision `#1`, signal
  `smart-money`, tx
  `0x2a2f94c40e2b5c080bd330f43f3ce6bc6b05e054b6626ce3ab2716220f0d3211`.
- The 2026-06-10 backend proof-readiness pass reports `npm run
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

2. Confirm the profile still matches the sibling repository READMEs. Do not
   run `git status --short org-profile backend contracts frontend` from the
   shared parent. That command assumes the parent is a Git repository. Check
   each repository explicitly:

   ```bash
   for repo in org-profile backend contracts frontend; do
     git -C "$repo" status --short
   done
   ```

3. Run the profile/doc guards from `backend/` before changing public claims:

   ```bash
   node --import tsx --test src/lib/docs/github-profile-docs.test.ts src/lib/docs/github-profile-readme.test.ts
   ```

4. Capture the current short head before refreshing any public campaign
   snapshot from the repo you are updating:

   ```bash
   git rev-parse --short HEAD
   ```

5. Keep links pointed at the public `Langclaw-AI-Celo` repositories.
