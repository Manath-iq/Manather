# Security Policy

Thanks for helping keep Manather and its users safe.

## Reporting a vulnerability

**Please do not open a public issue for security problems.**

Report privately through GitHub:

- Open a [private security advisory](https://github.com/Manath-iq/Manather/security/advisories/new), or
- Contact the maintainer directly.

Please include:

- a description of the issue and its impact,
- the steps to reproduce (a proof of concept helps a lot),
- the app version (see **Manather → About**) and your macOS version.

We aim to acknowledge reports within a few days and will keep you updated as we
investigate and ship a fix. Once a fix is released, we're happy to credit you —
let us know if you'd prefer to stay anonymous.

## Supported versions

Manather is an actively developed, pre-1.0 app. Security fixes land in the
**latest release** — please make sure you're on the most recent
[`.dmg`](https://github.com/Manath-iq/Manather/releases/latest) before reporting.

## Security model — what to know

Manather is a **local-first macOS app**. Your library — files, metadata, prompts,
notes — lives only on your Mac under
`~/Library/Application Support/ManatherAssets/`. There is **no account, no
backend, and no telemetry**; nothing is uploaded anywhere unless *you* enable a
feature that talks out (see below).

### Your data and your keys
- The app works fully offline. It only reaches the network when you explicitly
  use a feature that needs it (e.g. generating a web-link screenshot, or an AI
  feature you configured).
- **AI provider API keys are stored in the macOS Keychain** — never in plain
  UserDefaults, logs, or the exported context packs.
- AI features only call the provider *you* connected, with *your* key.

### The built-in MCP server
Manather can act as a local MCP server so an AI agent can read from and write to
your library. It is designed to be safe by default:

- **Off by default** — you turn it on in **Settings → MCP Server**.
- **Loopback only** — it binds to `127.0.0.1` and is not reachable from other
  machines on your network.
- **Token-protected** — every request must carry a private `Authorization:
  Bearer` token shown in Settings.
- **Scoped capabilities** — per-capability permission toggles (browse / create /
  add / edit / export) let you decide exactly what an agent may do; disabled
  capabilities are hidden and rejected, and changes apply instantly.
- **Library operations only** — the API can manage assets, collections and
  exports. It is not a general-purpose file or shell endpoint.
- **Runs only while the app is open.**

### App Sandbox is disabled — on purpose
Manather ships with the macOS **App Sandbox turned off**. This is a deliberate
trade-off: the app detects and launches external CLI agents (Claude Code, Codex,
etc.) and reads their config files (e.g. `~/.claude/`), which the sandbox would
block. The practical consequence is that Manather runs with your normal user
permissions. To keep that safe, the app:

- only launches external tools **in response to your action**, and only from a
  **fixed list** of known agent commands — it never runs arbitrary commands;
- doesn't expose file or process access through the MCP API.

If you'd rather not have these capabilities, you can keep the MCP server off and
simply not connect any CLI agents.

### Distribution
Release `.dmg` builds are currently **not notarized** by Apple, which is why
macOS shows a Gatekeeper warning on first launch. If you want full assurance of
what you're running, you can always **[build from source](README.md#build-from-source)** —
the project has no third-party dependencies.
