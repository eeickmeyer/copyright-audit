# Changelog

All notable changes to this project are documented in this file.

## 2026-03-21

### Added
- Decopy-accelerated generate mode: when `decopy` is installed, generate
  mode runs decopy to seed the initial `debian/copyright`, then
  automatically switches to check+fix+yes to harden it with scanner
  cross-validation, DEP-5 normalization, and license text fetching.
  Falls back to the built-in generator when decopy is absent.
- Snap packaging: `snap/snapcraft.yaml` with core24 base, strict
  confinement, bundling scancode-toolkit (with serial pool patch for
  snap compatibility), licensecheck, decopy, git, and coreutils
- Loud license incompatibility banners in all three modes (generate,
  review, check) using `!`-character box warnings so conflicts are
  impossible to miss
- Scanner cross-validation: when ScanCode is the primary scanner,
  licensecheck and decopy are run as sanity checks and discrepancies
  are reported in both review (Test 19) and check (Section 12) modes
- Per-file copyright holder attribution tracking to prevent false
  attribution when a holder is detected in only a subset of a
  multi-file stanza's files
- Email deobfuscation: obfuscated emails such as
  "chris at kohlhoff dot com" and "oliver dot kowalke@gmail.com"
  are converted to proper addresses; parenthesized emails are
  normalized to angle brackets
- Fix 7 (normalize copyright lines): existing stanzas are re-parsed
  to correct year ordering (e.g., "4Front Technologies 1993-2006" →
  "1993-2006 4Front Technologies"), deobfuscate emails, and apply
  bracket normalization
- Fix 8 (strip inline common-license text): inline license bodies
  for licenses available under `/usr/share/common-licenses/` are
  replaced with a short reference, and a standalone `License:` block
  with the common-licenses path is added if not already present
- Yes-to-all / No-to-all in interactive fix mode: each prompt now
  accepts `A` (yes to all remaining) and `X` (no to all remaining);
  the end-of-check offer also accepts `A` to enter fix mode with all
  prompts auto-accepted
- Unresolved stub warning: after writing any copyright file, a loud
  warning lists every line that still contains a `FIXME`, `TODO`, or
  `PLACEHOLDER` token

### Fixed
- Scanner exit code capture: `set -e` no longer aborts before
  recording ScanCode's exit status
- Crash when no files have detected licenses in generate mode
  (`max()` on empty sequence)
- Unhelpful traceback on corrupt ScanCode JSON; now prints an
  actionable error message
- `git log` argument length overflow for large repos; copyright year
  inference now batches in chunks of 200 files
- Usage comment corrected from `copyright-check.sh` to
  `copyright-audit`
- Check mode section numbering gap (10 → 12, skipping 11) fixed to
  consecutive 10, 11, 12
- Redundant duplicate condition in public-domain URL check simplified
- Duplicate stanzas: Fix 1 no longer proposes new stanzas for files
  already covered by a specific (non-catch-all) stanza
- Placeholder copyright holders (`Unknown`, `FIXME`, `TODO`, `none`,
  `n/a`) are now filtered out of merged copyright output
- KDE `metadata.desktop` files added to metadata globs to prevent
  them from receiving their own stanzas
- Comma-separated authors (e.g., "Huw Wilkins, Cory Kontros, and
  Andrew Wedderburn") are now split into separate copyright lines
- Copyright year inference: when some authors in a merge have detected
  years but others do not, the yearless authors inherit peer years;
  falls back to git history or file modification time when no years
  are detected at all
- Corporate suffixes (Inc., Ltd., LLC, GmbH, AG, etc.) no longer
  cause erroneous author splitting on commas (e.g.,
  "Rep Invariant Systems, Inc." is kept as a single holder)
- Decopy progress bar now visible during generate mode (removed
  `--quiet` flag and stderr suppression)

## 2026-03-20

### Added
- Directory license and copyright inheritance for files without
  explicit headers
- Progress display during analysis for large scans (200+ files)
- Native Debian package detection with conditional `debian/*` stanza
  logic
- Directory-level and file-specific stanza generation in fix mode
- Email-based deduplication and Unicode normalization for copyright
  holder merging (e.g., preserves "Gräßlin" across stanzas)
- DEP-5-aware `Files: *` handling: holders from specific
  subdirectories are proposed as precise per-holder-group stanzas
  rather than being added to the catch-all baseline
- Exclusion of `debian/copyright` and `.bak` files from scanning to
  prevent feedback loops

### Improved
- ScanCode integration with enhanced progress updates and error
  handling
- Interactive fix mode now offered automatically when issues are
  detected
- VCS directory exclusion and path processing in generate mode
- Copyright field formatting with column 80 wrapping and proper
  DEP-5 continuation indentation

## 2026-03-19

### Added
- Initial release with three operating modes: check, generate, review
- DEP-5 format validation (field ordering, whitespace, required fields)
- License mismatch detection comparing scanner results against
  declared stanzas
- Copyright holder auditing with fuzzy matching (year ranges, `(c)`
  markers, whitespace normalization)
- License text completeness verification with Creative Commons
  handling
- Automatic license text fetching from SPDX and Creative Commons APIs
- Non-free / DFSG detection (SSPL, BUSL, Elastic, JSON, PolyForm,
  CC-NC, CC-ND, and more)
- Stanza coverage analysis (uncovered files and stale globs)
- License compatibility checks (Apache-2.0 + GPL-2-only, EPL + GPL,
  CDDL + GPL, and more)
- False-positive filtering for autoconf boilerplate, LICENSE files,
  and build files
- SPDX-to-DEP-5 normalization for 130+ scanner IDs
- Interactive fix mode with stanza creation, stale glob removal,
  format corrections, and license text insertion
- Automatic `debian/*` stanza proposal based on packager identity
  detection (`$DEBFULLNAME`/`$DEBEMAIL`, `git config`, system user)
- GNU General Public License v3.0 or later
