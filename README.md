# Copyright Audit

A Debian `debian/copyright` file generator, validator, and reviewer. Scans source trees using [ScanCode Toolkit](https://github.com/aboutcode-org/scancode-toolkit) or `licensecheck`.

## Features

- **Three modes**: check (default), generate, and review
- **DEP-5 validation**: field ordering, whitespace, required fields
- **License mismatch detection**: scanner results vs. declared stanzas
- **Copyright holder auditing**: missing/extra authors with fuzzy matching, Unicode name preservation, and DEP-5-aware `Files: *` handling (proposes precise stanzas instead of polluting the catch-all)
- **License text completeness**: verifies License blocks have full text
- **Automatic license fetching**: from SPDX and Creative Commons APIs
- **Non-free / DFSG detection**: SSPL, BUSL, CC-NC, CC-ND, and more
- **Coverage analysis**: uncovered files and stale globs
- **Compatibility checks**: Apache + GPL-2-only, EPL + GPL, CDDL + GPL, etc.
- **Interactive fix mode**: proposes stanzas, removes stale globs, corrects formatting, adds missing holders and license text; normalizes year ordering and email addresses in existing stanzas; replaces inline license bodies for common licenses with `/usr/share/common-licenses/` references; each prompt accepts `A` (yes to all) or `X` (no to all) to batch-answer all remaining fixes
- **Unresolved stub warning**: after writing, any remaining `FIXME`/`TODO`/`PLACEHOLDER` tokens are reported with their line numbers
- **Email deobfuscation**: converts "alice at example dot com" and similar patterns to proper addresses; normalizes parenthesized emails to angle brackets
- **Corporate suffix awareness**: names ending in Inc., Ltd., LLC, GmbH, and similar suffixes are never split on commas
- **130+ SPDX-to-DEP-5 mappings**: GFDL, Creative Commons 1.0–4.0, AGPL, EPL, CDDL, OSL families

## Requirements

- `python3`
- **ScanCode Toolkit** (recommended): `pip install scancode-toolkit`
- Or **licensecheck** (basic): `apt install licensecheck`
- Optional: internet access for license text fetching (`--no-fetch` to disable)

## Usage

```bash
chmod +x copyright-audit

# Validate existing debian/copyright
./copyright-audit [source-dir]

# Generate a new copyright file
./copyright-audit generate -o debian/copyright [source-dir]

# Review for archive upload
./copyright-audit review [source-dir]

# Auto-fix all issues
./copyright-audit --fix --yes [source-dir]
```

### Options

| Option | Description |
|---|---|
| `-e, --exclude PATTERN` | Glob pattern to exclude (repeatable) |
| `-o, --output FILE` | Output file (generate mode) |
| `-f, --fix` | Enter interactive fix mode |
| `--yes` | Auto-accept all fixes (no prompts) |
| `-v, --verbose` | Include likely false positives |
| `--no-fetch` | Skip license text downloads |
| `-j, --jobs N` | Parallel ScanCode workers (default: nproc) |
| `-h, --help` | Show help |

## License

GNU General Public License v3.0 or later — see [LICENSE](LICENSE).
