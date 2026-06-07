# Langclaw AI Celo

Langclaw is a Celo-first AI alpha, data, and strategy workspace. It helps users
analyze smart-money flow, liquidity anomalies, protocol momentum, and DEX pair
history, then records source-backed agent decisions and strategy paper-trade
proofs on Celo.

The current build is analysis-first. It does not custody assets, sign swaps, or
execute live-funds trades. Strategy Lab supports Celo backtests and deterministic
paper-trade proofs so signals can be reviewed without execution risk.

## Repositories

Organization: [Langclaw-AI-Celo](https://github.com/Langclaw-AI-Celo)
Live app: [langclawcelo.vercel.app](https://langclawcelo.vercel.app)

| Repository | Stack | Purpose |
| --- | --- | --- |
| [frontend](https://github.com/Langclaw-AI-Celo/frontend) | Next.js, React, RainbowKit, Wagmi, AI SDK | User workspace, MiniPay-aware wallet flow, Celo Intelligence, Usage, Watchlist, Strategy Lab, and Proof Center |
| [backend](https://github.com/Langclaw-AI-Celo/backend) | Node HTTP API, TypeScript, Supabase, OpenAI, OpenClaw | Wallet/API auth, research workflow, billing ledger, proof anchoring, automation, provider orchestration, and Celo eligibility tooling |
| [contracts](https://github.com/Langclaw-AI-Celo/contracts) | Foundry, Solidity, OpenZeppelin | Celo proof registry, strategy journal, and USDT usage vault contracts |

## Product Coverage

| Area | What users get |
| --- | --- |
| Celo Intelligence | Smart-money summaries, holder-flow checks, liquidity anomaly detection, protocol momentum, risk notes, and source gaps |
| Alpha Watchlist | Saved Celo intelligence signals for follow-up review |
| Strategy Lab | Dune-backed Celo liquidity momentum backtests and deterministic paper-trade proof records |
| Proof Center | Celo registry decisions and strategy proof history |
| MiniPay path | Celo mainnet wallet access and USDT usage-credit flow |
| Automation | Scheduled monitoring, run history, in-app notifications, and Telegram linking |

## Celo Proof Layer

| Item | Value |
| --- | --- |
| Product chain | Celo mainnet `42220` |
| `LangclawRegistry` | `0xe69755e4249c4978c39fbe847ca9674ce7af3505` |
| `LangclawTradingJournal` | `0x69984c20176704685236fd633192d7de1c13a5ec` |
| `LangclawUsageVault` | `0x837a2948586de4e7638c742f99e520ffc049bcf7` |
| Celo USDT deposit token | `0x48065fbBE25f71C9282ddf5e1cD6D6A887483D5e` |
| ERC-8004 identity registry | `0x8004A169FB4a3325136EB29fA0ceB6D2e539a432` |
| Celo ERC-8004 agent ID | `9109` |
| ERC-8004 registration tx | `0x1b7cb74378db42551a3cbc81dcd560f337df1593d4ef1cd70ee44ff269bdc7f3` |
| Self Agent ID | `133` |
| Self Agent ID registration tx | `0x3c7d0cc69f77d2aef5ab21bfe703d0f33f7037d5e2162209d78b23b5c3f1cde6` |
| Agent owner / recorder | `0x2cA915EF6be8D2D48ccD3c5dAF715546AF873A4c` |
| Latest decision proof | Decision `#38`, signal `campaign-backend-proof`, tx `0x4485061e6e6151bc51c106f025b7d062468121595ca5cb4198f7307ea5ec5f06` |
| Latest decision proof run | `github-backend-650d33c-2026-06-06` |
| Latest decision proof evidence | `https://github.com/Langclaw-AI-Celo/backend/commit/650d33c80a2a54c5a706c79722a6eeeaa5dd4fd8` |
| Latest Self-linked decision proof | Decision `#1`, signal `smart-money`, tx `0x2a2f94c40e2b5c080bd330f43f3ce6bc6b05e054b6626ce3ab2716220f0d3211` |

The live Celo proof transactions above were rechecked in the
2026-06-07 backend eligibility and proof-readiness pass. `npm run
check:celo-proof` now returns `ready` because the default proof path prefers
the ERC-8004 campaign agent `9109`. Self Agent ID `133` remains part of the
public proof story for linked-proof and human-verification flows. The
contracts remain source-verified on Celoscan according to the backend
eligibility runbook.

## Demo Prompts

```text
Find smart-money accumulation on Celo
```

```text
Detect liquidity anomalies on Celo DEX pairs
```

```text
Rank Celo protocols by TVL and yield momentum
```

```text
Analyze holder flow and smart-money signals on Celo token 0x471EcE3750Da237f93B8E339c536989b8978a438
```

## Safety And Scope

- Langclaw does not execute live trades or move user funds for trading.
- Celo USDT deposits are app usage credits, not model-provider funding.
- Strategy Lab paper trades are deterministic proof records, not exchange
  orders.
- Provider failures are surfaced as source gaps instead of hidden.
- Strong agent decisions can be anchored through `LangclawRegistry`; Strategy
  Lab outcomes can be anchored through `LangclawTradingJournal`.

## Verification

Backend:

```bash
npm run check:eligibility
npm run check:celo-proof
npm run typecheck
npm test
```

Frontend:

```bash
pnpm typecheck
pnpm build
```

Contracts:

```bash
forge build
forge test
```

Public entrypoint:

```text
https://langclawcelo.vercel.app
```
