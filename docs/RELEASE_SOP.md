# Release SOP

This is the canonical and unique release procedure for this repository.
`RELEASE_CHECKLIST.md` is a subordinate quality checklist; `INSTALL.md` is the
customer install and rollback guide. There are no separate platform packaging
SOPs because the release artifact is a cross-platform Rime configuration archive,
not a signed application or installer.

## Project

- Repository: `GravityPoet/rime-smart-simplified`
- GitHub remote: `git@github.com:GravityPoet/rime-smart-simplified.git`
- Default release branch: `main`
- Package ecosystem: Rime configuration, Lua extensions, dictionaries, and cross-platform installer entry points
- Package manager: none

## Versioning

- Version source: annotated Git tag and matching GitHub Release
- Tag format: SemVer with a `v` prefix; the first stable release is `v1.0.0`
- Bump rule: incompatible install/config behavior = major; user-visible compatible
  capability = minor; compatible fixes/docs/packaging = patch
- Changelog source: commits since the previous release plus source-backed README behavior
- Release types: stable by default; prerelease tags must use a SemVer prerelease suffix

## Preconditions

- Required tools: `git`, authenticated `gh`, `bash`, `lua`, `luac`,
  `rime_deployer`, `curl`, `python3`, `shasum`, `unzip`, and `actionlint`
- Dependency install: none; CI installs `lua5.4` and `librime-bin`
- Required clean state: `git status --short --branch` has no unrelated changes
- Required remote state: local `main` is based on current `origin/main`, the target
  tag and Release do not exist, and the operator has repository admin permission
- Required CI state: the exact release commit has successful GitHub Actions checks
  named `verify`, `windows-installer`, `macos-rime`, `linux-frontends`, and
  `upstream-freshness` before the tag is pushed
- Primary path: local verification and archive creation, push `main`, wait for CI,
  push the annotated tag, then create the GitHub Release with archive and checksum
- CI evidence path: inspect the tracked workflow, then query the commit Check Runs
  endpoint with `gh api` by exact SHA and require all five named GitHub Actions
  checks to complete successfully. Do not use `gh workflow list`, `gh run list`, or
  the Actions Run Detail endpoint while those endpoints are returning 503

### Release quality gates

- Critical non-stubbed workflow: `./scripts/verify.sh` runs Lua behavior tests,
  install-manifest and private-state preservation tests, live upstream digest parsing,
  an isolated install, and a real `rime_deployer --build`
- Release archive boundary: `scripts/check_release_archive.sh` creates a temporary
  `git archive` from the exact release ref, verifies all platform entry points and
  rejects ownership manifests, benchmark output, user/runtime databases, model
  files, build output, and rollback/backup data
- Local fixtures/models/services: the release excludes `*.gram`; the installer obtains
  the rolling upstream grammar model and validates its GitHub asset digest
- Pinned upstream assets: `UPSTREAM_ASSETS.lock.json` records the exact Wanxiang
  dictionary commit/blob SHAs, the current LTS grammar digest, and the prediction
  asset metadata. `scripts/check_upstream_freshness.sh --strict` must pass for a
  release; it performs metadata/API checks only and never writes the live Rime
  directory or downloads user data.
- Marketed-locale strict i18n: not applicable; this package has no localized application UI
- Platform package assets: no application binary or updater metadata is distributed;
  the ZIP includes a macOS `.command`, Windows `.cmd`/PowerShell entry point, and the
  existing POSIX shell installer for the Rime configuration data
- macOS signing/TCC identity continuity: not applicable; the archive contains Rime
  configuration only and does not ship or replace `Squirrel.app`
- Customer-facing install path: `README.md`, `README.zh-CN.md`, `INSTALL.en.md`, and
  `INSTALL.md`; configuration rollback uses the installer's timestamped backup

## Commands

All commands run from the repository root.

### Tool and privacy preflight

```bash
command -v git gh bash lua luac rime_deployer curl python3 shasum unzip actionlint
gh auth status
git status --short --branch
git remote -v
git fetch origin --prune --tags
git rev-list --left-right --count origin/main...HEAD

if git grep -nEi 'YOUR_HANDLE|YOUR_EMAIL|YOUR_PHONE|YOUR_PRIVATE_PROJECT' -- \
  ':!RELEASE_CHECKLIST.md' ':!docs/RELEASE_SOP.md'; then
  exit 1
fi

if git ls-files | rg '(^|/)(.*\.bak($|\.)|.*\.backup\.|.*\.userdb($|/)|predict\.db$|.*\.gram$|\.rime-smart-simplified\.install-manifest$|benchmark-results\.jsonl$|context_boost.*\.tsv$|pin_by_select.*\.tsv$|runLog\.txt$)'; then
  printf 'Tracked runtime or backup data must not enter a release archive.\n' >&2
  exit 1
fi
test -z "$(git ls-files '*.gram')"

source_urls="$(rg -o 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+' \
  README.md README.zh-CN.md INSTALL.md INSTALL.en.md THIRD_PARTY.md | sed 's/^[^:]*://' | sort -u)"
while IFS= read -r source_url; do
  http_status="$(curl -sSL -o /dev/null -w '%{http_code}' \
    --max-time 30 "$source_url")"
  test "$http_status" = 200
done <<EOF
$source_urls
EOF
```

### Verify

```bash
./scripts/verify.sh
git diff --check
./scripts/check_release_archive.sh

# Local integrity check (works without network and must always pass)
./scripts/check_upstream_freshness.sh --local-only --strict

# Release/CI freshness check (requires GitHub API access)
./scripts/check_upstream_freshness.sh --strict
```

The exact release commit must then pass GitHub Actions `CI`. The isolated
`rime_deployer` build is the macOS/Linux package-compatibility proof; do not modify
the operator's live Rime user directory merely to satisfy the release gate.

### Upstream dictionary/model maintenance

`cn_dicts_wanxiang/` is a checked-in snapshot of only the seven dictionaries
listed in `UPSTREAM_ASSETS.lock.json`. The update command is read-only by default:

```bash
./scripts/update_dicts.sh
```

To refresh those seven files, preserving the unrelated `cn_dicts/` user/domain
词库, run:

```bash
./scripts/update_dicts.sh --apply
./scripts/check_upstream_freshness.sh --local-only --strict
./scripts/verify.sh
```

`--apply` downloads only the pinned GitHub commit, verifies every Git blob SHA
and a minimum line-count ratio, creates a timestamped sibling backup, updates
`.upstream-commit`, and atomically refreshes the dictionary section of the lock
file. A failed download or safety check leaves that dictionary unchanged; if a
later verification fails, restore the seven files and `.upstream-commit` from the
reported `cn_dicts_wanxiang.backup.<timestamp>` directory, then rerun the local
lock check. Never replace `cn_dicts/41448.dict.yaml`, `smart_terms.dict.yaml`, or
`smart_finance.dict.yaml` with this command.

The grammar release is intentionally rolling. The lock freshness policy currently
flags dictionary commits or grammar assets older than 180 days. The old
`librime-predict` `data-1.0` release has no GitHub digest; its known SHA-256,
size, and timestamp remain pinned and the installer verifies the SHA-256 after
download. A stale warning is allowed in ordinary non-strict local development,
but release/CI must use `--strict`. Exit status `2` means GitHub/API/network
metadata was unavailable; callers may use `--offline-ok` for an explicitly
offline local check, but never for a release.

### Package and checksums

Set the intended new SemVer tag explicitly. The command refuses to reuse the
old example version:

```bash
: "${RELEASE_VERSION:?Set RELEASE_VERSION to a new tag such as v1.1.0}"
case "$RELEASE_VERSION" in
  v[0-9]*.[0-9]*.[0-9]*) ;;
  *) printf 'RELEASE_VERSION must look like v1.2.3\n' >&2; exit 2 ;;
esac
test "$RELEASE_VERSION" != v1.0.0
RELEASE_DIR="$(mktemp -d /tmp/rime-smart-simplified-release.XXXXXX)"
ARTIFACT="rime-smart-simplified-${RELEASE_VERSION}.zip"

git archive --format=zip \
  --prefix="rime-smart-simplified-${RELEASE_VERSION}/" \
  --output="$RELEASE_DIR/$ARTIFACT" HEAD

(
  cd "$RELEASE_DIR"
  shasum -a 256 "$ARTIFACT" > "$ARTIFACT.sha256"
  unzip -t "$ARTIFACT"
)

EXTRACT_DIR="$(mktemp -d /tmp/rime-smart-simplified-extract.XXXXXX)"
RIME_TEST_DIR="$(mktemp -d /tmp/rime-smart-simplified-rime.XXXXXX)"
  unzip -q "$RELEASE_DIR/$ARTIFACT" -d "$EXTRACT_DIR"
  test -x "$EXTRACT_DIR/rime-smart-simplified-${RELEASE_VERSION}/Install-on-macOS.command"
  test -f "$EXTRACT_DIR/rime-smart-simplified-${RELEASE_VERSION}/Install-on-Windows.cmd"
  test -f "$EXTRACT_DIR/rime-smart-simplified-${RELEASE_VERSION}/scripts/install.ps1"
  RIME_USER_DIR="$RIME_TEST_DIR" \
  "$EXTRACT_DIR/rime-smart-simplified-${RELEASE_VERSION}/scripts/install.sh" \
  --dry-run --no-download-gram
```

### Release notes

For the first stable release, describe only capabilities evidenced by `README.md`,
`INSTALL.md`, verification output, and the commits in the tagged tree. For later
releases, use `git log <previous-tag>..HEAD`. Keep the notes file outside the tracked
tree and do not expose private paths, credentials, disabled features, or internal
failure details.

### GitHub Release

```bash
set -euo pipefail
: "${RELEASE_VERSION:?Set RELEASE_VERSION to the reviewed new tag}"
: "${RELEASE_DIR:?Set RELEASE_DIR to the verified package directory}"
: "${RELEASE_NOTES:?Set RELEASE_NOTES to the reviewed release-notes file}"
test -s "$RELEASE_NOTES"
ARTIFACT="rime-smart-simplified-${RELEASE_VERSION}.zip"
git push origin main

TARGET_SHA="$(git rev-parse HEAD)"
REQUIRED_CHECKS="verify windows-installer macos-rime linux-frontends upstream-freshness"
CI_VERIFIED=0
API_FAILURES=0
attempt=1
while [ "$attempt" -le 30 ]; do
  if ! CHECK_RUNS="$(gh api \
    -H 'Accept: application/vnd.github+json' \
    "repos/GravityPoet/rime-smart-simplified/commits/$TARGET_SHA/check-runs" \
    --jq '.check_runs[] | select(.app.slug == "github-actions") | [.name, .id, .status, (.conclusion // ""), .details_url] | @tsv')"
  then
    API_FAILURES=$((API_FAILURES + 1))
    if [ "$API_FAILURES" -ge 6 ]; then
      printf 'GitHub Check Runs API failed six consecutive times.\n' >&2
      exit 1
    fi
    sleep 5
    attempt=$((attempt + 1))
    continue
  fi

  API_FAILURES=0
  PENDING=0
  for required_check in $REQUIRED_CHECKS; do
    CHECK_LINE="$(printf '%s\n' "$CHECK_RUNS" | awk -F '\t' -v name="$required_check" '
      $1 == name && ($2 + 0) >= max_id { line = $0; max_id = ($2 + 0) }
      END { if (line != "") print line }
    ')"
    if [ -z "$CHECK_LINE" ]; then
      printf 'CI %s: not reported yet\n' "$required_check"
      PENDING=1
      continue
    fi

    CHECK_STATUS="$(printf '%s\n' "$CHECK_LINE" | cut -f3)"
    CHECK_CONCLUSION="$(printf '%s\n' "$CHECK_LINE" | cut -f4)"
    CHECK_URL="$(printf '%s\n' "$CHECK_LINE" | cut -f5-)"
    printf 'CI %s: status=%s conclusion=%s url=%s\n' \
      "$required_check" "$CHECK_STATUS" "$CHECK_CONCLUSION" "$CHECK_URL"
    case "$CHECK_STATUS" in
      completed)
        if [ "$CHECK_CONCLUSION" != success ]; then
          printf 'Required check failed: %s (%s)\n' "$required_check" "$CHECK_CONCLUSION" >&2
          exit 1
        fi
        ;;
      queued|in_progress|waiting|requested|pending)
        PENDING=1
        ;;
      *)
        printf 'Unexpected GitHub check status for %s: %s\n' \
          "$required_check" "$CHECK_STATUS" >&2
        exit 1
        ;;
    esac
  done

  if [ "$PENDING" -eq 0 ]; then
    CI_VERIFIED=1
    break
  fi
  sleep 5
  attempt=$((attempt + 1))
done
test "$CI_VERIFIED" -eq 1

git tag -a "$RELEASE_VERSION" -m "$RELEASE_VERSION"
git push origin "$RELEASE_VERSION"
gh release create "$RELEASE_VERSION" \
  "$RELEASE_DIR/$ARTIFACT" \
  "$RELEASE_DIR/$ARTIFACT.sha256" \
  --repo GravityPoet/rime-smart-simplified \
  --verify-tag --title "$RELEASE_VERSION" --notes-file "$RELEASE_NOTES"
```

### Distribution verification

```bash
: "${RELEASE_VERSION:?Set RELEASE_VERSION to the published tag}"
ARTIFACT="rime-smart-simplified-${RELEASE_VERSION}.zip"
gh release view "$RELEASE_VERSION" --repo GravityPoet/rime-smart-simplified \
  --json url,tagName,isDraft,isPrerelease,assets

DOWNLOAD_DIR="$(mktemp -d /tmp/rime-smart-simplified-download.XXXXXX)"
gh release download "$RELEASE_VERSION" --repo GravityPoet/rime-smart-simplified \
  --dir "$DOWNLOAD_DIR"
(
  cd "$DOWNLOAD_DIR"
  shasum -a 256 -c "$ARTIFACT.sha256"
  unzip -t "$ARTIFACT"
)
```

## Rollback

- Before `main` push: discard only release-owned local edits or revert the release
  commit; never overwrite unrelated work
- After `main` push but before tag push: use a new `git revert` commit and wait for CI;
  do not force-push public `main`
- After tag/Release publication: preserve the immutable tag and assets, mark the
  Release as prerelease if customer impact requires an immediate warning, then ship
  a corrective patch release; do not delete or overwrite public artifacts
- Installed configuration: restore the timestamped backup documented in `INSTALL.md`

## Fuse Conditions

- Stop before external writes if `origin/main` changed after preflight, the working
  tree includes unrelated changes, the target tag/Release exists, auth is missing,
  or the target commit cannot be identified exactly
- Stop before tag push if local verification or target-commit CI fails
- Stop before Release creation if the archive test, platform entry-point checks,
  isolated installer dry run, or
  checksum verification fails
- After publication, do not use destructive tag/release deletion as an automatic rollback

## Failure Ledger

| Date | Version/Tag | Command | Error Signature | Root Cause | Fix | Prevention |
| --- | --- | --- | --- | --- | --- | --- |
| 2026-07-20 | `v1.0.0` | `gh release list --repo GravityPoet/rime-smart-simplified --limit 30 --json tagName,name,isDraft,isPrerelease,publishedAt,createdAt,url` | `Unknown JSON field: "url"` | `gh release list` in gh 2.86.0 does not expose `url` in its JSON schema | Omit `url`; use `gh release view <tag> --json url,...` once a tag is known | Check the field list reported by `gh` before scripting non-obvious JSON fields |
| 2026-07-20 | `v1.0.0` | `gh workflow list --repo GravityPoet/rime-smart-simplified --all` | `HTTP 503: No server is currently available to service your request` | GitHub's Actions workflows-list endpoint returned 503 while repository metadata and commit check-runs remained available | Read `.github/workflows/ci.yml` and query `commits/<sha>/check-runs` for the exact release SHA | After two identical workflows-list 503 responses, stop retrying that endpoint and use exact-SHA check-run evidence |
| 2026-07-20 | `v1.0.0` | `gh repo view mirtlecn/rime-lmdg ...`; `gh search repos rime-lmdg --owner mirtlecn ...` | `Could not resolve to a Repository`; `Invalid search query` | The release link check manually reconstructed a URL that was not present in the tracked docs, producing a false first diagnosis | Re-read the source and extract URLs directly with `rg` before validating them | Never hand-copy or infer the input set for a source-link gate |
| 2026-07-20 | `v1.0.0` | `gh repo view wongstz/rime-lmdg ...` | `Could not resolve to a Repository with the name 'wongstz/rime-lmdg'` | `README.md` retained a stale attribution URL while `INSTALL.md`, `THIRD_PARTY.md`, and the installer already used the live canonical `amzxyz/RIME-LMDG` source | Update the README attribution to `https://github.com/amzxyz/RIME-LMDG` and validate all extracted source URLs | Make source-link validation part of every release preflight and require HTTP 200 after redirects |
| 2026-07-20 | `v1.0.0` | `gh run list --repo GravityPoet/rime-smart-simplified --commit 18c2cac... --workflow CI ...` | `couldn't fetch workflows ... HTTP 503` | The documented fallback still used `--workflow CI`, which immediately queried the unavailable workflows-list endpoint | Replace `gh run list` with exact-SHA commit check-runs evidence | A workflows-endpoint fallback must avoid commands that resolve workflow metadata through that endpoint |
| 2026-07-20 | `v1.0.0` | `gh run list --repo GravityPoet/rime-smart-simplified --commit 18c2cac... --json databaseId,workflowName,event ...` | `failed to get runs ... HTTP 503 ... actions/workflows` | In gh 2.86.0, `gh run list` still queried the workflows-list endpoint without a `--workflow` flag, so the first fallback remained coupled to the outage | Query `commits/<sha>/check-runs` and require the `verify` check from `github-actions` to succeed | Do not assume `gh run list` is independent of workflow discovery |
| 2026-07-20 | `v1.0.0` | `gh api repos/GravityPoet/rime-smart-simplified/actions/runs/29710729304 --jq .status` | `HTTP 503: No server is currently available to service your request` | The raw Actions Run Detail endpoint also returned transient 503 while the commit Check Runs endpoint exposed the completed result | Use `commits/<sha>/check-runs`, with at most six consecutive transport retries, and distinguish API failure from a failed CI conclusion | Tag only after exact-SHA check-run evidence reports `status=completed` and `conclusion=success` |
