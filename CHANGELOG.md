# Changelog

All notable changes to this project are documented in this file.

## 2026-04-01

### Fixed
- SPDX-to-DEP-5 normalization: added `mit/x11` → `Expat` mapping so
  license names like `MIT/X11` (as emitted by decopy/licensecheck) are
  correctly normalized; previously they passed through unchanged,
  causing Fix 3b to fail to resolve the stub license text

## 2026-03-31

### Added
- `--cache-dir DIR` option: reuse scancode/licensecheck/decopy results
  from a directory, skipping re-scanning when cached output files already
  exist. Dramatically speeds up iterative runs (e.g. ~42 s vs ~25 min
  for the digikam 9.0 source tree)
- Fix 0c3: implausible copyright holder removal — filters out code
  fragments, boilerplate strings, template variables, and other
  non-person text that scanners sometimes misidentify as copyright
  holders (e.g. `nullptr`, `@author`, `${PROJECT_NAME}`)
- Fix 0c4: packager-as-copyright removal — strips the debian packager's
  identity from Copyright fields in upstream (non-`debian/*`) stanzas,
  since the packager is not an upstream copyright holder
- Fix 0c5: trim catch-all Copyright to AUTHORS entries — for the
  `Files: *` catch-all stanza, filters copyright holders to only those
  whose name or email appears in the project's AUTHORS/CONTRIBUTORS
  file, preventing every per-file author from polluting the project-
  level attribution
- Fix 6b: glob consolidation — collapses explicit per-file entries into
  `dir/*` globs when all files in a directory share the same stanza,
  with a safety check to avoid overriding different-author stanzas via
  DEP-5 last-match-wins semantics
- Fix 0c2-final: late-stage FIXME resolution — runs after all other
  fix steps to resolve `Copyright: FIXME` stanzas introduced by Fix 1,
  Fix 3, and other steps. Uses four strategies: (1) fnmatch scanner
  data lookup, (2) file header reading (Copyright:/Author: patterns,
  prioritizing source-code extensions), (3) directory COPYRIGHT/AUTHORS
  files with broad attribution heuristics, (4) XML `<developer_name>`
  metadata and path-based inference (e.g. OpenStreetMap)
- Patch-file false-positive filter: detects when a `.patch`/`.diff`
  file's scanner-detected licenses all originate from unified diff
  context lines (not the patch's own license header) and clears them
  from scan results, preventing false LGPL/GPL stanzas from SPDX
  identifiers in patched source code
- CC-GPL SPDX-to-DEP-5 mappings: added `cc-gpl-2.0` → `GPL-2`,
  `cc-gpl-3.0` → `GPL-3`, `cc-lgpl-2.1` → `LGPL-2.1`,
  `cc-lgpl-3.0` → `LGPL-3` (and short-form variants)

### Fixed
- Fix 0c2 now also resolves existing `Copyright: FIXME` lines (not
  just missing Copyright fields): treats FIXME as needing resolution
  and replaces the line in place rather than inserting a duplicate
- Fix 2b now removes entire stanzas when all files are zero-evidence
  (previously skipped them, leaving orphaned stanzas with FIXME
  copyright that could never be resolved)
- Fix 0c2-final handles files in subdirectories under glob patterns:
  e.g. `elegant/resources/*` now correctly descends into `css/`,
  `images/`, `js/` subdirectories to find source files with copyright
  headers, and prioritizes source-code extensions (`.js`, `.css`,
  `.xml`) over binary files

## 2026-03-30

### Added
- Fix 0b upstream author inference — Upstream-Contact is now inferred
  from the project's source forge (GitHub API owner profile), package
  metadata files (setup.py, setup.cfg, pyproject.toml, package.json),
  or git history, in that order. The debian/control Maintainer
  (packager) is used only as a last resort, since the packager is
  typically not the upstream author
- Fix 0c2: add missing Copyright to Files stanzas — when decopy emits
  a Files stanza without a Copyright field, infers holders from
  scanner data; for Files: *, queries the upstream source forge
  (GitHub API repo owner + creation year) or package metadata before
  falling back to packager identity
- Fix 0b re.MULTILINE fix — the Upstream-Contact insertion regex now
  uses `re.MULTILINE` so it correctly matches `Upstream-Name:` on
  lines other than the first
- Exclude `debian/copyright.*` from scanning — the bash exclusion
  patterns now cover `debian/copyright.*` (not just `.bak`), preventing
  stale test artifacts like `copyright.raw` from polluting scanner
  results and leaking foreign copyright holders into debian/* stanzas
- Fix 1c: cross-validation-backed license correction — when a specific
  stanza declares the wrong license (e.g. decopy said MIT-open-group
  but scancode detected HPND-sell-variant), Fix 1c consults the
  secondary scanner results (licensecheck and/or decopy). If at least
  two scanners agree on the detected license, the tool offers to
  update the stanza in-place. Previously, Fix 1 skipped files with
  existing specific stanzas, assuming the declaration was intentional,
  so review mode would flag a mismatch that check+fix never corrected

### Fixed
- Fix 0b: GitHub URL regex now strips `#fragment` and `/tree/...`
  sub-paths before extracting owner/repo, preventing API failures on
  URLs like `https://github.com/user/repo#readme`
- Fix 0b: `setup.cfg` author parsing now handles INI-style unquoted
  values (`author = John Doe`) in addition to the quoted form used by
  `setup.py` (`author="John Doe"`)
- Fix 0b: `pyproject.toml` author parsing now handles the common
  inline-array format (`authors = [{name = "..."}]`) in addition to
  the table-array format (`[[project.authors]]`)
- Fix 0b: header stub replacement now covers `Source: FIXME` (from
  built-in generator) in addition to `Source: TODO` (from decopy);
  also replaces `Upstream-Name: FIXME` and `Upstream-Contact: FIXME`
  with inferred values instead of skipping them

## 2026-03-29

### Fixed
- Fix 3b: common-licenses reference validation — standalone license
  blocks referencing `/usr/share/common-licenses/<name>` where the
  file does not actually exist (e.g. CC-BY-SA-3.0, which is not
  shipped in common-licenses) are now detected and replaced with the
  full license text fetched from SPDX/CC, instead of being silently
  skipped. Previously, decopy could generate a CC-BY-SA-3.0 block
  with a bogus common-licenses pointer that Fix 3b would trust
  because it only checked for the presence of the path string, not
  whether the referenced file exists on disk

## 2026-03-26

### Changed
- Fix 2 overhauled: replaced regex-based stale glob removal with
  paragraph-level superfluous detection and removal. Now handles three
  cases: (1) stanzas where all file patterns match no files (removed
  entirely), (2) stanzas with some stale patterns (stale patterns
  stripped, stanza kept), and (3) stanzas redundant with the catch-all
  `Files: *` (same license and copyright holder subset — removed
  entirely). Orphaned standalone `License:` blocks no longer referenced
  by any `Files:` stanza are cleaned up automatically

### Added
- `check_superfluous()` function: identifies superfluous file patterns
  and entire stanzas in `debian/copyright` — stale patterns (matching
  no scanned file), fully stale stanzas, and catch-all-redundant
  stanzas (bidirectional `licenses_compatible()` + copyright holder
  subset check)
- Review mode Test 10b: reports superfluous stanzas and patterns with
  `[WARN]`/`[PASS]` status; integrated into the four-tier VERDICT
  via `superfluous_ok`
- Check mode SECTION 6: reports entirely superfluous stanzas and
  partially superfluous patterns with per-stanza details and a
  `--fix` tip; count included in `total_issues` summary

## 2026-03-22

### Added
- `--export FILE` option for review mode: writes a full-detail export of
  all findings (mismatches, false positives, undeclared licenses,
  uncovered files, holder mismatches, etc.) with no truncation
- Review mode Test 3 now shows inline mismatch details (detected vs.
  declared license, affected files) instead of just a count
- Decopy `--progress` flag added to all three invocation sites
  (check/review sanity checks and generate mode) so progress bars
  are visible during long scans
- Cross-validation generalized: when licensecheck is the primary
  scanner and decopy is available, decopy is now used as the sanity-
  check scanner (previously cross-validation only worked with
  scancode as primary). When all three scanners are available,
  the primary cross-validates against each secondary independently
  (e.g. scancode vs licensecheck AND scancode vs decopy). All
  reporting labels dynamically reflect the actual scanner pairs
- Two-of-three consensus in cross-validation: when all three scanners
  ran and a file is flagged by pairwise comparison, the tool checks
  whether any two scanners agree on the license family. If so, the
  file is downgraded from `[WARN]` to `[INFO]` ("2-of-3 consensus");
  only files where all three disagree remain `[WARN]`
- XMP metadata enrichment for raster images: extracts `dc:creator`,
  `cc:license`, `dc:rights`, `xmpRights:WebStatement`,
  `photoshop:Credit`, and `xmp:CreateDate` from embedded XMP packets
  in PNG, JPEG, TIFF, WebP, GIF, BMP, and ICO files — no external
  dependencies (byte-string search + stdlib `xml.etree`). License
  and copyright holder extracted from XMP override scanner heuristics,
  matching the existing SVG RDF/XML behaviour
- Snap: `base-files` stage-package (in its own part, filtered to
  `usr/share/common-licenses/` only) so common-licenses references
  resolve correctly under strict confinement
- Binary garbage copyright filter: `_is_plausible_copyright()` rejects
  strings with high non-ASCII/non-printable character ratios (< 70%
  printable ASCII or < 3 printable chars), eliminating false copyright
  holders extracted from binary files (PNG, GIF, etc.)
- DEP-5 license block boilerplate: `_dep5_common_license_body()` now
  generates full preamble text for all common license families (GPL,
  LGPL, AGPL, GFDL, Apache, MPL, Artistic, BSD, CC0) with proper
  "or later version" clauses and common-licenses pointers, matching
  the format used in real Debian packages. Applied in generate mode,
  Fix 3 (missing blocks), Fix 3b (empty/stub blocks), and Fix 8
  (inline replacement)
- DEP-5 body line wrapping: `_wrap_dep5_body()` re-wraps any license
  body lines exceeding 79 columns at word boundaries, keeping the
  generated copyright file within standard column limits
- Fix 0c: FSF boilerplate copyright removal — strips "Free Software
  Foundation" from Copyright fields in GPL-family stanzas (both in
  existing stanzas and scanner-generated content in generate/fix mode)
- Fix 0d: License text file path removal — removes REUSE-spec
  `LICENSES/*.txt` paths from per-file stanzas (covered by `Files: *`)
- `LICENSES/*` and `licenses/*` added to `_METADATA_GLOBS` so the
  REUSE spec license text directory is treated as metadata
- Generate mode `debian/*` stanza: non-native packages now get a
  `debian/*` stanza with packager identity and GPL-2+ license, matching
  the behavior of `--fix` mode (interactive prompt, editable)
- Fix 5 year update: when the packager is already listed in the
  `debian/*` stanza but the current year is missing, offers to extend
  the year range (e.g. `2024-2025` → `2024-2026`)
- Review mode verdict: license incompatibility is now a blocker —
  `VERDICT: BLOCKED` takes priority over all other verdicts when
  `check_license_compatibility()` finds conflicts

### Fixed
- False positive when checking `/usr/share/common-licenses/` references
  under snap strict confinement: the script now falls back to
  `$SNAP/usr/share/common-licenses/` when the host path is inaccessible
- License file copyright noise: files named LICENSE, COPYING, etc. are
  now excluded from copyright holder detection, eliminating false
  positives like FSF's copyright on the GPL text being reported as a
  project holder
- Copyright holder "mismatches" reclassified: declared-but-not-detected
  holders (common for icon themes and data-only projects) are now
  `[INFO]` instead of `[WARN]`, with the note "normal for files
  without embedded headers"; undeclared holders remain `[WARN]`
- Cross-validation now displays DEP-5 normalized license identifiers
  (e.g. `GPL-3` instead of `GPL-3.0-only`) on both primary and
  secondary sides for consistent, readable output
- Cross-validation skips project-level metadata files (LICENSE, COPYING,
  AUTHORS, CONTRIBUTORS) that routinely differ between scanners without
  indicating a real problem
- Snap: `PYTHONUNBUFFERED=1` added to snap environment so tqdm-based
  progress bars (e.g. from decopy) are visible in strict confinement
- Generate mode no longer writes a `.bak` file (uses `_decopy_generated`
  flag to detect the generate→check pipeline instead of checking mode)
- Fix 5 `has_debian_glob` now checks `working_text` directly instead of
  the stale `stanzas` list, so a `debian/*` stanza removed by earlier
  fixes (e.g. Unknown license resolution) is correctly detected as
  missing and re-created with the packager's identity
- Fix 5 `debian/*` stanza packager check extracts copyright lines from
  `working_text` instead of the stale `stanza_copyrights` dict,
  ensuring year-update logic works with normalized content

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
