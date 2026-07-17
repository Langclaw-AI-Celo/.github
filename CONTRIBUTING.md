# Contributing to Langclaw AI Celo

Thank you for helping improve Langclaw. We welcome focused fixes, tests,
documentation, and product improvements that support the Celo-first roadmap.

## Choose the Right Repository

Langclaw uses separate repositories. Open your issue or pull request in the
repository that owns the change.

| Repository | Scope |
| --- | --- |
| [frontend](https://github.com/Langclaw-AI-Celo/frontend) | Next.js interface, wallet flows, accessibility, and client tests |
| [backend](https://github.com/Langclaw-AI-Celo/backend) | API routes, research providers, auth, billing, proof services, and automation |
| [contracts](https://github.com/Langclaw-AI-Celo/contracts) | Solidity contracts, Foundry tests, and deployment scripts |
| [.github](https://github.com/Langclaw-AI-Celo/.github) | Organization profile and shared community files |

Each repository has its own Git history. Run Git commands inside the repository
you plan to change.

## Before You Start

1. Search existing issues and pull requests.
2. Open an issue for a large feature or behavior change.
3. Keep security reports private. Follow [SECURITY.md](SECURITY.md), and do not
   disclose suspected vulnerabilities in a public issue.
4. Confirm that your proposal does not introduce live-funds trading or hidden
   custody behavior.

## Local Setup

Use the runtime declared by the target repository.

Frontend:

```bash
corepack enable
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm test
pnpm build
```

Backend:

```bash
npm ci
npm audit --audit-level=low
npm run typecheck
npm run test:coverage
npm run build
```

Contracts:

```bash
forge fmt --check
forge test
forge build
```

## Change Guidelines

- Keep each change small and independently useful.
- Add or update tests when behavior changes.
- Preserve public API and contract compatibility unless the proposal clearly
  documents a reviewed migration.
- Never commit private keys, wallet signatures, access tokens, or production
  secrets.
- Keep Celo addresses and proof claims consistent with verified project docs.
- Use clear names and short comments. Explain why when the code cannot do so.

## Commits

Use a focused commit subject such as:

```text
fix(auth): reject expired wallet sessions
test(vault): cover partial withdrawal accounting
docs(org): clarify repository setup
```

Do not use empty commits. Do not mix unrelated cleanup with the requested
change.

## Pull Requests

Your pull request should include:

- A concise problem statement.
- A summary of the solution.
- The exact checks you ran.
- Screenshots for visible interface changes.
- Migration or rollback notes when relevant.
- Links to related issues.

Maintainers may ask you to split a large pull request. Review feedback should
produce new commits during review. Maintainers can clean the branch history
when the contribution is ready to merge.

By contributing, you agree to follow the organization community standards.
