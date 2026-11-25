# Releasing

The repository holds two CurseForge projects, each named by its TOC's `## X-Curse-Project-ID`:

- **AME** (`AzerothMercantileExchange.toc`; its zip also carries `AzerothMercantileExchange_History` and the embedded
  `LibAMEChart-1.0`), released from release branches by release-please.
- **AME Crafting Data** (`AzerothMercantileExchange_Crafting`), the recipe data from the game, released on its own
  whenever the game's data changes (see Crafting data below).

Every release goes through a pull request and CI. Nobody uploads to CurseForge by hand, and nobody pushes to `main`
or a `release/*` branch directly.

## Branches

- **`main`** is where work lands, by pull request.
- **`release/<major>.<minor>`** (`release/0.5`, `release/0.6`, ...) is one per release line, cut from `main` when the
  line is ready. Every release of that line, betas included, is a tag on it (`v0.5.0-beta.2`).
- A fix for a released line goes to its release branch by pull request, and to `main` too (cherry-pick, or a second
  pull request), so the next line has it.

Both are protected by the "Protect main" ruleset: a pull request, the `format`, `lint-and-test` and `commitlint`
checks, rebase merging only, and an approval from the code owner. The owner's own pull requests can be merged without an approval; nobody,
the owner included, can push to these branches directly.

## Commits

Pull requests are rebase-merged: every commit lands on the branch as it is, and release-please reads each one. So
every commit must be a [conventional commit](https://www.conventionalcommits.org/) (`commitlint` checks them all,
with `commitlint.config.mjs`): a header of at most 100 characters, body lines of at most 120. Tidy a branch with an
interactive rebase before it merges; a "wip" or "fix typo" commit fails the check.

| Commit | Changelog | Version |
|---|---|---|
| `feat: ...` | New | next beta |
| `fix: ...` | Fixes | next beta |
| `perf: ...` | Faster | next beta |
| `revert: ...` | Reverted | next beta |
| `docs:`, `style:`, `refactor:`, `test:`, `build:`, `ci:`, `chore:` | not listed | none |

Write the subject of a `feat`, `fix` or `perf` commit for players: it is a line they read in the changelog on
CurseForge.

## Cutting a release line

Actions > **Cut release branch** > Run workflow, with the line (`0.6`). It creates `release/0.6` from `main` with an
empty commit whose `Release-As` footer makes the first proposal `0.6.0-beta.1` (or the version given in "first").

## Releasing

1. Each push to a release branch runs **Release** (`.github/workflows/release.yml`). release-please keeps one release
   pull request open on that branch: the next version and the `CHANGELOG.md` entry, from the commits since the last
   release.
2. **Merging that pull request is the release.** release-please tags it and makes the GitHub release.
3. The same workflow then checks the tagged commit (luacheck, busted), builds the zip (`scripts/package.sh`),
   uploads it to CurseForge with the release notes as its changelog (`scripts/release.sh`), attaches the zip to the
   GitHub release, and opens an issue to archive the files it replaces.
4. Archive those files in the CurseForge authors dashboard and close the issue. CurseForge has no API for archiving.

Betas: the line releases `x.y.0-beta.N` while `prerelease` is `true` in `release-please-config.json`. To release the
line as stable, set `"prerelease": false` on its release branch by pull request; the next release pull request
proposes `x.y.0`.

Before 1.0 there is no major bump: a breaking change (`feat!:`, or a `BREAKING CHANGE:` footer) raises the minor
version, and a `feat` on a released line the patch (`0.5.0` -> `0.5.1`), so a line stays on its branch
(`bump-minor-pre-major`, `bump-patch-for-minor-pre-major`). A new line is cut by hand (Cutting a release line).

## Crafting data

Hands-off: **Crafting data** (`.github/workflows/crafting-data.yml`) asks wago.tools once a day for the latest WoW
Forever build. When the generated data differs from main's, it checks it, opens a pull request (`fix(data): crafting
data for WoW Forever build ...`, with the generator's summary), waits for its checks and merges it. The merge runs
**Crafting data release** (`.github/workflows/crafting-data-release.yml`): the next `data-v1.0.N` tag on main's
commit, the upload to the data project with the summary as its changelog, and an issue to archive the older data
files. Data the same as the latest `data-v*` tag releases nothing; a failure opens an issue instead.

The data folder is left out of AME's changelog and versions (`exclude-paths` in `release-please-config.json`).

## One-time setup

- Secret `CURSEFORGE_CI_API_TOKEN`: a CurseForge API token (authors dashboard > API tokens).
- Secret `RELEASE_PLEASE_TOKEN`: a fine-grained GitHub token for this repository only, with Contents, Pull requests
  and Workflows read/write. release-please opens its pull requests with it, so they run CI (pull requests opened with
  the default token don't), "Cut release branch" pushes with it, so the new branch starts **Release**, and the
  crafting data job opens and merges its pull requests with it (as yours: no approval needed).
- Each addon's CurseForge project ID in its TOC: `## X-Curse-Project-ID: <id>` (public, on the project page).

`scripts/release.sh --check` (with a local `.env`) verifies the CurseForge token and lists the game versions that
match the TOC's interface.

## Before this

Releases up to 0.5.0-beta.1 were uploaded by hand; their changelogs are in `docs/changelog/`.
