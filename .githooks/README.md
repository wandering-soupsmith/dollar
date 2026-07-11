# Git hooks

Version-controlled hooks for this repo. They are shared (unlike `.git/hooks/`) but git
does not enable them automatically — each clone must point git at this directory once:

```bash
git config core.hooksPath .githooks
```

## `pre-commit` — secret scanner

Blocks a commit when the **added** lines of the staged diff look like they contain a
private key or secret. It scans additions only, so pre-existing content and transaction
hashes (also `0x` + 64 hex) never trip it. It flags:

- PEM private-key blocks (`-----BEGIN … PRIVATE KEY-----`)
- a literal 64-hex value on a line mentioning `priv` / `secret` / `mnemonic`
  (e.g. a hardcoded `--private-key 0x…`); a `$VAR` reference is fine
- BIP39-style mnemonics (12+ words after a `mnemonic` / `seed phrase` keyword)
- staged real `.env` files (`.env`, `.env.sepolia`, …); `*.example` / `*.sample` /
  `*.template` are allowed

**Allowlist** a genuine false positive by appending `allowlist secret` to that line.
**Bypass** in an emergency (discouraged): `git commit --no-verify`.
