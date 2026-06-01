defmodule HexUrlMigrator do
  @moduledoc """
  An escript to safely migrate HexDocs URLs to the 2026 format.
  Ensures the directory is a clean Git repository before making changes.
  """

  @public_regex ~r{(https?://)?\bhexdocs\.pm/([a-zA-Z0-9_]+)}
  @org_regex ~r{(https?://)?\b([a-zA-Z0-9_-]+)\.hexdocs\.pm/([a-zA-Z0-9_]+)}

  def main(args) do
    # Parse CLI flags
    {parsed, _args, _invalid} = OptionParser.parse(args, switches: [dry_run: :boolean])
    dry_run? = Keyword.get(parsed, :dry_run, false)

    if dry_run? do
      IO.puts("✨ Running in DRY-RUN mode. No files will be modified.\n")
    else
      # Perform strict safety checks if we intend to write changes
      validate_git_env!()
    end

    IO.puts("Scanning for files...")

    files =
      Path.wildcard("**/*.{ex,exs,md}")
      |> Enum.reject(&String.starts_with?(&1, ["deps/", "_build/"]))

    if files == [] do
      IO.puts("No matching .ex, .exs, or .md files found.")
    else
      run_migration(files, dry_run?)
    end
  end

  defp run_migration(files, dry_run?) do
    stats =
      Enum.reduce(files, {0, 0}, fn path, {files_changed, total_replacements} ->
        content = File.read!(path)
        {content_1, count_1} = migrate_org_urls(content)
        {content_2, count_2} = migrate_public_urls(content_1)
        total_file_replacements = count_1 + count_2

        if total_file_replacements > 0 do
          if dry_run? do
            IO.puts("[Dry-Run] Would update #{total_file_replacements} URLs in: #{path}")
          else
            File.write!(path, content_2)
            IO.puts("Updated [#{total_file_replacements} changes]: #{path}")
          end

          {files_changed + 1, total_replacements + total_file_replacements}
        else
          {files_changed, total_replacements}
        end
      end)

    {files_changed, total_replacements} = stats

    mode_label =
      if dry_run?, do: "[Dry-Run] Mode finished. Total prospective", else: "Successfully modified"

    IO.puts("\nMigration complete!")
    IO.puts("#{mode_label} #{files_changed} file(s) with #{total_replacements} replacement(s).")
  end

  # --- Git Safety Infrastructure ---

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
        IO.puts("⚠️ Warning: You have uncommitted changes in your repository.")

        unless confirm?("Do you want to proceed anyway?") do
          IO.puts("Migration aborted by user.")
          System.halt(0)
        end

      _ ->
        IO.puts(:stderr, "❌ Error executing 'git status'.")
        System.halt(1)
    end
  end

  defp confirm?(question) do
    input = IO.gets("#{question} [y/N]: ") |> String.trim() |> String.downcase()
    input in ["y", "yes"]
  end

  # --- Transform Logic ---

  defp migrate_public_urls(content) do
    count = length(Regex.scan(@public_regex, content))

    updated_content =
      Regex.replace(@public_regex, content, fn _, protocol, package ->
        "#{protocol}#{String.replace(package, "_", "-")}.hexdocs.pm"
      end)

    {updated_content, count}
  end

  defp migrate_org_urls(content) do
    matches = Regex.scan(@org_regex, content)
    valid_matches = Enum.reject(matches, fn [_, _, org, _] -> org == "hexdocs" end)
    count = length(valid_matches)

    updated_content =
      Regex.replace(@org_regex, content, fn full_match, protocol, org, package ->
        if org == "hexdocs", do: full_match, else: "#{protocol}#{org}.hexorg.pm/#{package}"
      end)

    {updated_content, count}
  end
end
