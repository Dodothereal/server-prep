# Contributing to server-prep

Thanks for helping. All kinds of help are welcome:

- **Test it** on your OS, VPS provider or hardware, and tell us what worked or broke.
- **Report bugs** or **suggest ideas** in [Issues](https://github.com/exceev-consulting/server-prep/issues).
- **Ask questions** in [Discussions](https://github.com/exceev-consulting/server-prep/discussions).
- **Send a pull request**: bug fixes, support for another panel, new checks, clearer docs.

Issues labelled [`good first issue`](https://github.com/exceev-consulting/server-prep/labels/good%20first%20issue) are a good place to start.
For a big change, open an issue first so we can agree on the approach.

Security problems: **don't open a public issue**. See [SECURITY.md](SECURITY.md).

## Set up

There is nothing to build. You need bash 5 and, for linting, [ShellCheck](https://github.com/koalaman/shellcheck).

```bash
git clone https://github.com/exceev-consulting/server-prep.git && cd server-prep
```

**Never test on a server you care about.** Use a throwaway VM or a cheap VPS:
`multipass launch 24.04`, an LXD/Incus VM, or a cloud VPS you delete afterwards.

## Before you open a pull request

1. **Syntax and lint** (CI runs the same):
   ```bash
   bash -n server-prep.sh server-audit.sh server-preconfig.sh
   shellcheck -S warning server-prep.sh server-audit.sh server-preconfig.sh extras/github-runners/*.sh
   ```
2. **Dry run** on a test server, then a real run if your change modifies the system:
   ```bash
   sudo ./server-prep.sh --dry-run --only <step>
   sudo ./server-audit.sh
   ```
3. Say in the PR **what you tested**: OS and version, VPS or dedicated server, panel, dry run or real run.

## Rules for the scripts

- **Everything that changes the system goes through the helpers:** `run` (respects `--dry-run`), `write_file`,
  `set_kv`, `backup_file`, `pkg_install` (installs only what is missing), `svc_disable`.
- **A step can run twice safely.** Check the current state first and only change what is missing.
- **apt:** always pass `"${APT_OPTS[@]}"`. A fresh server often runs apt in the background at boot.
- **Third-party apt repos:** download the key, **check its fingerprint**, store it in `/etc/apt/keyrings/`,
  use `signed-by`, and pin the repo at priority 900.
- **Downloads** (like ufw-docker): pin a version and check a SHA-256.
- **Works with any panel:** use `PANEL`, `PANEL_PUBKEY`, `PANEL_ACCESS`, `PANEL_IP` and `${PANEL_LABEL}` in messages.
  Code for one panel only goes behind `[[ ${PANEL,,} == <name> ]]`.
- **A new or changed step** also updates `server-prep.conf.example`, the step table in `README.md`,
  and adds a check to `server-audit.sh` (INFO when optional).
- **No secrets and no real infrastructure** in the repo: tokens, keys, real IPs or hostnames.
  Use examples like `web-01` and `192.168.1.50`.
- **Simple words** in messages and docs. Many users are not security experts.
- Style: 4 spaces, `[[ ]]`, quote variables. `.editorconfig` has the basics.

[CLAUDE.md](CLAUDE.md) has the full list of conventions and the bugs already fixed (don't bring them back).
If you use [Claude Code](https://claude.com/claude-code), the `/add-step` skill walks through the checklist.

## Commits and pull requests

- One topic per pull request. Small is easier to review.
- PR title: `<script or area>: <what changes>`, for example `server-audit.sh: detect Openship`.
  The title becomes the release note line, so make it clear.
- Pull requests are **squash-merged**. You don't need to sign your commits: the merge commit on `main`
  is signed by GitHub.

## Releases (maintainers)

1. Bump `PREP_VERSION` in `server-prep.sh` (and `AUDIT_VERSION` in `server-audit.sh` if it changed).
2. Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md` with the highlights.
3. Commit, then tag and push:
   ```bash
   git tag -a vX.Y.Z -m "server-prep X.Y.Z" && git push origin vX.Y.Z
   ```
The `release` workflow checks the version, lints, and creates the GitHub release: the `CHANGELOG.md`
section, the merged pull requests grouped by label, and the scripts with a `SHA256SUMS` file.

## License

By contributing, you agree that your work is released under the [MIT License](LICENSE).
Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
