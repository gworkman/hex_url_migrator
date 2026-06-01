defmodule HexUrlMigratorTest do
  use ExUnit.Case

  describe "migrate_content/1" do
    test "migrates public hexdocs URLs" do
      content = "Check https://hexdocs.pm/my_package for details."
      expected = "Check https://my-package.hexdocs.pm for details."

      assert {^expected, 1, ["https://my-package.hexdocs.pm"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates public hexdocs URLs without protocol" do
      content = "Visit hexdocs.pm/another_package today."
      expected = "Visit another-package.hexdocs.pm today."

      assert {^expected, 1, ["another-package.hexdocs.pm"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates multiple public URLs" do
      content = "Link 1: hexdocs.pm/pkg_1, Link 2: hexdocs.pm/pkg_2"
      expected = "Link 1: pkg-1.hexdocs.pm, Link 2: pkg-2.hexdocs.pm"

      assert {^expected, 2, ["pkg-1.hexdocs.pm", "pkg-2.hexdocs.pm"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates organization hexdocs URLs" do
      content = "See https://my_org.hexdocs.pm/my_package."
      expected = "See https://my_org.hexorg.pm/my_package."

      assert {^expected, 1, ["https://my_org.hexorg.pm/my_package"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates organization hexdocs URLs with dashes in org" do
      content = "See https://my-org.hexdocs.pm/my_package."
      expected = "See https://my-org.hexorg.pm/my_package."

      assert {^expected, 1, ["https://my-org.hexorg.pm/my_package"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "does not migrate hexdocs.pm as an organization (handled as public)" do
      # If it's hexdocs.pm/something, it should be public migration
      content = "https://hexdocs.pm/phoenix"
      expected = "https://phoenix.hexdocs.pm"

      assert {^expected, 1, ["https://phoenix.hexdocs.pm"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates both public and org URLs in the same content" do
      content = """
      Public: hexdocs.pm/ecto
      Org: my_org.hexdocs.pm/ecto_sql
      """

      expected = """
      Public: ecto.hexdocs.pm
      Org: my_org.hexorg.pm/ecto_sql
      """

      assert {^expected, 2, urls} = HexUrlMigrator.migrate_content(content)
      assert "my_org.hexorg.pm/ecto_sql" in urls
      assert "ecto.hexdocs.pm" in urls
    end

    test "does not match unintended strings" do
      content = "This is not a hexdocs link: google.com/search?q=hexdocs.pm"
      assert {^content, 0, []} = HexUrlMigrator.migrate_content(content)
    end

    test "replaces underscores with dashes only in public URL package names" do
      content = "hexdocs.pm/my_long_package_name"
      expected = "my-long-package-name.hexdocs.pm"

      assert {^expected, 1, ["my-long-package-name.hexdocs.pm"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "preserves underscores in organization names and package names for org URLs" do
      # The requirements say for org URLs we just change .hexdocs.pm to .hexorg.pm/
      content = "my_org.hexdocs.pm/my_package"
      expected = "my_org.hexorg.pm/my_package"

      assert {^expected, 1, ["my_org.hexorg.pm/my_package"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates public URLs with additional paths, anchors, and parameters" do
      content = "https://hexdocs.pm/phoenix/Phoenix.HTML.html#content?key=val"
      expected = "https://phoenix.hexdocs.pm/Phoenix.HTML.html#content?key=val"

      assert {^expected, 1, ["https://phoenix.hexdocs.pm/Phoenix.HTML.html#content?key=val"]} =
               HexUrlMigrator.migrate_content(content)
    end

    test "migrates org URLs with additional paths, anchors, and parameters" do
      content = "https://my_org.hexdocs.pm/my_package/api-reference.html#summary?v=1"
      expected = "https://my_org.hexorg.pm/my_package/api-reference.html#summary?v=1"

      assert {^expected, 1,
              ["https://my_org.hexorg.pm/my_package/api-reference.html#summary?v=1"]} =
               HexUrlMigrator.migrate_content(content)
    end
  end
end
