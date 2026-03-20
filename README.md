# Copyright Audit

A Debian `debian/copyright` file generator, validator, and reviewer. Scans source trees for license and copyright information using [ScanCode Toolkit](https://github.com/aboutcode-org/scancode-toolkit) (SPDX license database) when available, falling back to `licensecheck` otherwise.

## Features

- **Three operating modes**: check, generate, and review
- **DEP-5 format validation**: structural compliance checks (field ordering, whitespace, required fields, etc.)
- **License mismatch detection**: compares scanner results against declared `debian/copyright` stanzas
- **License text completeness**: verifies standalone License blocks contain full legal text, with special handling for Creative Commons licenses
- **Automatic license text fetching**: downloads full license text from SPDX and Creative Commons APIs for generate and fix modes (disable with `--no-fetch`)
- **Non-free / DFSG detection**: flags non-DFSG-compliant licenses (SSPL, BUSL, Elastic, JSON, PolyForm, CC-NC, CC-ND, and more) in all modes
- **Stanza coverage analysis**: finds source files not matched by any `Files:` glob and stale globs that match no file
- **License compatibility checks**: detects conflicts like Apache-2.0 + GPL-2-only, EPL-1.0 + GPL, CDDL + GPL, OSL + GPL, QPL + GPL, OpenSSL + GPL, BSD-4-Clause + GPL, and more — checks both declared and detected licenses
- **False-positive filtering**: classifies autoconf boilerplate, LICENSE text files, and build files to reduce noise
- **SPDX-to-DEP-5 normalization**: maps 130+ scanner IDs to standard Debian license identifiers, including full GFDL family, all Creative Commons versions (1.0–4.0), and AGPL/EPL/CDDL/OSL families
- **Interactive fix mode**: proposes and applies fixes to `debian/copyright` (new stanzas, stale glob removal, format corrections, fetched license text)

## Requirements

- `python3`
- At least one license scanner:
  - **ScanCode Toolkit** (recommended) — `pip install scancode-toolkit`
  - **licensecheck** (basic, Debian-native) — `apt install licensecheck`
- Optionally, **decopy** for additional coverage checks — `apt install python3-decopy`
- Internet access for automatic license text fetching (optional; use `--no-fetch` to disable)

## Usage

```bash
chmod +x copyright-audit.sh
```

### Modes

#### check (default)

Validates an existing `debian/copyright` against the actual source tree. Produces a sectioned report covering DEP-5 format, license mismatches, false positives, license text completeness, compatibility, non-free warnings, detected licenses, stanza coverage, and files without license headers.

```bash
./copyright-audit.sh check [options] [source-dir]
```

#### generate

Scans a source tree and produces a new `debian/copyright` on stdout. Groups files by license/copyright and creates DEP-5 stanzas with a catch-all, per-directory globs, and license text blocks. Full license text is automatically fetched from SPDX/Creative Commons when available; licenses in `/usr/share/common-licenses/` are referenced by path. Warns about non-free licenses and compatibility conflicts.

```bash
./copyright-audit.sh generate [options] [source-dir]
./copyright-audit.sh generate -o debian/copyright .
```

#### review

Produces a structured pass/fail report suitable for archive review, with a final verdict. Checks both declared and detected licenses for compatibility and non-free issues.

```bash
./copyright-audit.sh review [options] [source-dir]
```

### Options

| Option | Description |
|---|---|
| `-e, --exclude PATTERN` | Glob pattern to exclude from scan (repeatable) |
| `-o, --output FILE` | Write generated copyright to FILE (generate mode) |
| `-f, --fix` | Interactively fix issues found (check mode only) |
| `--yes` | Auto-accept all fixes with `--fix` (no prompts) |
| `-v, --verbose` | Show all mismatches including likely false positives |
| `--no-fetch` | Don't download license text from SPDX/CC (use FIXME stubs) |
| `-j, --jobs N` | Parallel ScanCode workers (default: nproc) |
| `-h, --help` | Show help |

If `source-dir` is omitted, the current directory is used.

### Examples

```bash
# Validate debian/copyright in the current source tree
./copyright-audit.sh

# Generate a new copyright file with auto-fetched license text
./copyright-audit.sh generate -o debian/copyright /path/to/source

# Generate without network access (FIXME stubs only)
./copyright-audit.sh generate --no-fetch -o debian/copyright /path/to/source

# Review with exclusions
./copyright-audit.sh review -e "vendor/*" -e "third_party/*" /path/to/source

# Auto-fix all detected issues
./copyright-audit.sh check --fix --yes /path/to/source

# Verbose check with 4 scanner jobs
./copyright-audit.sh check -v -j 4 /path/to/source
```

## License

This project is licensed under the GNU General Public License v3.0 or later — see the [LICENSE](LICENSE) file for details.
