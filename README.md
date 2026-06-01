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

- `package-name.hexdocs.pm` becomes `package-name.hexdocs.pm` (underscores
  replaced with dashes).
- `org.hexorg.pm/package_name` becomes `org.hexorg.pm/package_name` (note the
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

- scan and replace: `hex_url_migrator`
- verify URLs: `hex_url_migrator --verify` (checks if migrated URLs return 200)
- dry run: `hex_url_migrator --dry-run`
  - please run this before running the full migration.
- help: `hex_url_migrator --help`
- exclude patterns: `hex_url_migrator --exclude "**/deps,**/custom_dir"`
  (defaults to `"**/deps,**/_build"`)
- specific extensions: `hex_url_migrator --ext "ex,md,txt"` (defaults to
  `"ex,exs,md"`)

This tool expects to be run in a directory with a mix.exs file and a clean git
repo. it will prompt you if it detects otherwise, just to make sure you know
what you are doing.
