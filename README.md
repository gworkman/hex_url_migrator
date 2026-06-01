# HexUrlMigrator

`HexUrlMigrator` is a standalone CLI tool (built as an Elixir escript) designed
to automatically upgrade HexDocs URLs within your Elixir packages to match the
new 2026 security standard.

It safely scans all `.ex`, `.exs`, and `.md` files in a project, remapping
legacy documentation URLs while ensuring your local development workspace
remains safe and protected from accidental overwrites.

## Motivation & Background

As of several days ago, HexDocs now hosts each package's docs in a separate
subdomain. This change is related to security updates from the recent ecosystem
audit - see the blog post here:
[Hex.pm Security Audit](https://hex.pm/blog/security-audit).

Here's what the changes look like:

- `hexdocs.pm/package_name` becomes `package-name.hexdocs.pm` (underscores
  replaced with dashes).
- `org.hexdocs.pm/package_name` becomes `org.hexorg.pm/package_name` (note the
  top level domain change from `hexdocs.pm` to `hexorg.pm`)

This package just does a simple find and replace for these urls in your package.
It is in no way optimized, so for large projects this might be a very slow
operation.

---

## Installation

You can install `HexUrlMigrator` globally on your machine directly from the
GitHub repository using Mix:

```bash
mix escript.install git https://github.com/gworkman/hex_url_migrator
```

## Usage

- Dry run: `hex_url_migrator --dry-run`
  - _Please_ run this before running the full migration.
- Scan and replace: `hex_url_migrator`

Note: it is best to run the tool with a clean git repo, in case you need to
undo. The tool will ask if you want to proceed if it detects uncommitted
changes.
