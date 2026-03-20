# Changelog

All notable changes to this project are documented in this file.

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
