# Security Policy

Langclaw handles wallet authentication, API credentials, usage credits, and
on-chain proof records. Please report security concerns carefully.

## Supported Versions

We review security fixes for the current default branch of each public
Langclaw AI Celo repository. Older commits, forks, and unofficial deployments
do not receive security updates.

## Report a Vulnerability

Do not open a public issue for an unpatched vulnerability.

Use the target repository's **Security** tab and select **Report a
vulnerability** when that option is available. If private reporting is not
available, contact a repository maintainer through their GitHub profile first.
Ask for a private reporting channel. Do not include exploit details in the
initial public message.

Include this information in the private report:

- The affected repository, commit, route, contract, or deployment.
- A clear description of the security impact.
- Reproduction steps or a minimal proof of concept.
- Required permissions and user interaction.
- Known affected assets, wallets, or data.
- A suggested fix, if you have one.

Remove private keys, access tokens, wallet signatures, personal data, and live
funds from every proof of concept.

## Response Process

We target these response times:

- Acknowledgment within three business days.
- Initial assessment within seven business days.
- A progress update at least every fourteen days while the report remains
  open.

We will confirm the affected component, assess severity, prepare a fix, and
coordinate disclosure with the reporter. Complex issues may need more time. We
will explain material delays.

## Disclosure

Please keep the report private until maintainers publish a fix or approve
disclosure. After remediation, we may publish a GitHub Security Advisory with
credit to the reporter. Tell us if you prefer to remain anonymous.

## Out of Scope

The following reports normally do not qualify unless they show direct security
impact:

- Automated scanner output without a reproducible issue.
- Missing headers that do not create an exploitable condition.
- Social engineering, spam, or physical attacks.
- Denial of service that requires sustained high-volume traffic.
- Vulnerabilities in unsupported forks or local configuration mistakes.
- Public Celo data that the application already labels as public.

Testing must not disrupt production, access another user's data, move live
funds, or interact with wallets you do not control.
