defmodule HexUrlMigrator do
  @moduledoc """
  An escript to safely migrate HexDocs URLs to the 2026 format.
  Ensures the directory is a clean Git repository before making changes.
  """

  @public_regex ~r{(https?://)?\bhexdocs\.pm/([a-zA-Z0-9_]+)([^ \n\t"'\(\)\[\]]*)?}
  @org_regex ~r{(https?://)?\b([a-zA-Z0-9_-]+)\.hexdocs\.pm/([a-zA-Z0-9_]+)([^ \n\t"'\(\)\[\]]*)?}

  def main(args) do
    # Parse CLI flags
    {parsed, _args, _invalid} =
      OptionParser.parse(args,
        switches: [
          dry_run: :boolean,
          exclude: :string,
          ext: :string,
          verify: :boolean,
          help: :boolean
        ],
        aliases: [h: :help]
      )

    if Keyword.get(parsed, :help, false) do
      print_help()
      System.halt(0)
    end

    dry_run? = Keyword.get(parsed, :dry_run, false)
    verify? = Keyword.get(parsed, :verify, false)
    exclude_raw = Keyword.get(parsed, :exclude, "**/deps,**/_build")
    ext_raw = Keyword.get(parsed, :ext, "ex,exs,md")

    exclude_patterns = String.split(exclude_raw, ",") |> Enum.map(&String.trim/1)
    extensions = String.split(ext_raw, ",") |> Enum.map(&String.trim/1)

    # confirm before starting search
    validate_mix_project!()

    if dry_run? do
      IO.puts("✨ Running in dry run mode. No files will be modified.\n")
    else
      # Perform strict safety checks if we intend to write changes
      validate_git_env!()
    end

    IO.puts("Scanning for files...")

    files = find_files(extensions, exclude_patterns)

    if files == [] do
      IO.puts("No matching files found.")
    else
      run_migration(files, dry_run?, verify?)
    end
  end

  defp print_help do
    IO.puts("""
    HexUrlMigrator - Safely migrate HexDocs URLs to the 2026 format.

    Usage:
      hex_url_migrator [options]

    Options:
      --dry-run          Show what would be changed without modifying files.
      --verify           Check if migrated URLs return 200 OK (requires internet).
      --exclude <pats>   Comma-separated glob patterns to exclude (default: **/deps,**/_build).
      --ext <exts>       Comma-separated extensions to scan (default: ex,exs,md).
      --help, -h         Show this help message.

    Examples:
      hex_url_migrator --dry-run
      hex_url_migrator --verify
      hex_url_migrator --exclude "**/custom_dir,**/tmp" --ext "ex,txt"
    """)
  end

  defp find_files(extensions, exclude_patterns) do
    glob =
      case extensions do
        [ext] -> "**/*.#{ext}"
        exts -> "**/*.{#{Enum.join(exts, ",")}}"
      end

    excluded_files =
      exclude_patterns
      |> Enum.flat_map(fn pattern ->
        # If the pattern is a directory, match all files inside it
        if String.ends_with?(pattern, "/") do
          Path.wildcard("#{pattern}**")
        else
          # Otherwise match files/dirs precisely
          Path.wildcard("#{pattern}/**") ++ Path.wildcard(pattern)
        end
      end)
      |> MapSet.new()

    Path.wildcard(glob)
    |> Enum.reject(&MapSet.member?(excluded_files, &1))
  end

  defp run_migration(files, dry_run?, verify?) do
    {stats, all_new_urls} =
      Enum.reduce(files, {{0, 0}, []}, fn path, {{files_changed, total_replacements}, acc_urls} ->
        content = File.read!(path)
        {updated_content, count, new_urls} = migrate_content(content)

        if count > 0 do
          if dry_run? do
            IO.puts("[Dry-Run] Would update #{count} URLs in: #{path}")
          else
            File.write!(path, updated_content)
            IO.puts("Updated [#{count} changes]: #{path}")
          end

          {{files_changed + 1, total_replacements + count}, acc_urls ++ new_urls}
        else
          {{files_changed, total_replacements}, acc_urls}
        end
      end)

    {files_changed, total_replacements} = stats

    mode_label =
      if dry_run?, do: "[Dry-Run] Mode finished. Total prospective", else: "Successfully modified"

    IO.puts("\nMigration complete!")
    IO.puts("#{mode_label} #{files_changed} file(s) with #{total_replacements} replacement(s).")

    if verify? and not Enum.empty?(all_new_urls) do
      verify_migrated_urls(all_new_urls)
    end
  end

  def verify_migrated_urls(urls) do
    IO.puts("\nVerifying migrated URLs...")

    urls
    |> Enum.uniq()
    |> Task.async_stream(
      fn url ->
        # try to not slam the server, sleep between 50 - 200 ms
        Enum.shuffle(50..200)
        |> List.first()
        |> Process.sleep()

        # Ensure we have a protocol for Req
        full_url = if String.starts_with?(url, "http"), do: url, else: "https://#{url}"

        case Req.get(full_url, redirect: false, retry: false) do
          {:ok, %{status: 200}} ->
            {:ok, url}

          {:ok, %{status: status}} ->
            {:error, url, "Status #{status}"}

          {:error, reason} ->
            {:error, url, inspect(reason)}
        end
      end,
      max_concurrency: 5,
      timeout: 10_000
    )
    |> Enum.reduce({0, 0}, fn
      {:ok, {:ok, _url}}, {success, failure} ->
        {success + 1, failure}

      {:ok, {:error, url, reason}}, {success, failure} ->
        IO.puts(:stderr, "❌ Verification failed for #{url}: #{reason}")
        {success, failure + 1}

      {:error, reason}, {success, failure} ->
        IO.puts(:stderr, "❌ Task failed: #{inspect(reason)}")
        {success, failure + 1}
    end)
    |> case do
      {s, 0} -> IO.puts("✅ All #{s} unique URLs verified successfully.")
      {s, f} -> IO.puts(:stderr, "⚠️ Verification finished: #{s} success, #{f} failure(s).")
    end
  end

  # --- Safety Infrastructure ---

  defp validate_git_env! do
    # 1. Check if it's a git repo
    case System.cmd("git", ["rev-parse", "--is-inside-work-tree"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      _ ->
        IO.puts(:stderr, "❌ Error: Current directory is not a Git repository.")
        System.halt(1)
    end

    # 2. Check for uncommitted changes
    case System.cmd("git", ["status", "--porcelain"]) do
      {"", 0} ->
        :ok

      {_changes, 0} ->
        IO.puts("\u26A0 Warning: You have uncommitted changes in your repository.")

        unless confirm?("Do you want to proceed anyway?") do
          IO.puts("Migration aborted by user.")
          System.halt(0)
        end

      _ ->
        IO.puts(:stderr, "❌ Error executing 'git status'.")
        System.halt(1)
    end
  end

  defp validate_mix_project! do
    unless File.exists?("mix.exs") do
      IO.puts("\u26A0 Warning: No mix.exs found in the current directory.")

      unless confirm?("Are you sure you want to run this here?") do
        IO.puts("Migration aborted by user.")
        System.halt(0)
      end
    end

    :ok
  end

  defp confirm?(question) do
    input = IO.gets("#{question} [y/N]: ") |> String.trim() |> String.downcase()
    input in ["y", "yes"]
  end

  # --- Transform Logic ---

  def migrate_content(content) do
    {content_1, count_1, urls_1} = migrate_org_urls(content)
    {content_2, count_2, urls_2} = migrate_public_urls(content_1)
    {content_2, count_1 + count_2, urls_1 ++ urls_2}
  end

  defp migrate_public_urls(content) do
    matches = Regex.scan(@public_regex, content)
    count = length(matches)

    new_urls =
      Enum.map(matches, fn [_, protocol, package, rest] ->
        url = "#{protocol}#{String.replace(package, "_", "-")}.hexdocs.pm#{rest}"
        trim_url(url)
      end)

    updated_content =
      Regex.replace(@public_regex, content, fn _, protocol, package, rest ->
        "#{protocol}#{String.replace(package, "_", "-")}.hexdocs.pm#{rest}"
      end)

    {updated_content, count, new_urls}
  end

  defp migrate_org_urls(content) do
    matches = Regex.scan(@org_regex, content)
    valid_matches = Enum.reject(matches, fn [_, _, org, _, _] -> org == "hexdocs" end)
    count = length(valid_matches)

    new_urls =
      Enum.map(valid_matches, fn [_, protocol, org, package, rest] ->
        url = "#{protocol}#{org}.hexorg.pm/#{package}#{rest}"
        trim_url(url)
      end)

    updated_content =
      Regex.replace(@org_regex, content, fn full_match, protocol, org, package, rest ->
        if org == "hexdocs", do: full_match, else: "#{protocol}#{org}.hexorg.pm/#{package}#{rest}"
      end)

    {updated_content, count, new_urls}
  end

  defp trim_url(url) do
    String.replace(url, ~r/[.,:;!?]$/, "")
  end
end
