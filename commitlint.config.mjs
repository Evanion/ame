// Every commit on a pull request is a conventional commit (the commitlint check, .github/workflows/commitlint.yml):
// pull requests are rebase-merged, so each commit lands on main as it is, and release-please reads each one for the
// changelog and the next version (RELEASING.md).
export default {
  extends: ["@commitlint/config-conventional"],
  rules: {
    // feat, fix, perf and revert are listed in the changelog (release-please-config.json); the rest are not
    "type-enum": [
      2,
      "always",
      ["feat", "fix", "perf", "revert", "docs", "style", "refactor", "test", "build", "ci", "chore"],
    ],
    // a subject may start with a name ("Auctions ..."), so sentence case is allowed beside lower case
    "subject-case": [2, "always", ["sentence-case", "lower-case"]],
    "header-max-length": [2, "always", 100],
    // the repository's line width (stylua, luacheck)
    "body-max-line-length": [2, "always", 120],
    "footer-max-line-length": [2, "always", 120],
  },
};
