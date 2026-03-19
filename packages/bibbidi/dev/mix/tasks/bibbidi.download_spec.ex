defmodule Mix.Tasks.Bibbidi.DownloadSpec do
  @shortdoc "Downloads and extracts the WebDriver BiDi CDDL spec files"

  @moduledoc """
  Downloads the `index.bs` (bikeshed) spec from the W3C WebDriver BiDi
  repository and extracts `remote.cddl` and `local.cddl` from its
  `<pre class="cddl">` blocks.

  The CDDL files are stored in `priv/cddl/` and should be checked into
  the repository.

      $ mix bibbidi.download_spec

  ## Options

  - `--force` - Overwrite existing files
  """

  use Mix.Task

  @spec_url "https://raw.githubusercontent.com/w3c/webdriver-bidi/refs/heads/main/index.bs"
  @dest_dir "priv/cddl"

  @impl true
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])
    force? = Keyword.get(opts, :force, false)

    local_dest = Path.join(@dest_dir, "local.cddl")
    remote_dest = Path.join(@dest_dir, "remote.cddl")

    if not force? and File.exists?(local_dest) and File.exists?(remote_dest) do
      Mix.shell().info("CDDL files already exist (use --force to overwrite)")
      return_files(local_dest, remote_dest)
    else
      Application.ensure_all_started(:inets)
      Application.ensure_all_started(:ssl)

      File.mkdir_p!(@dest_dir)

      Mix.shell().info("Downloading spec from #{@spec_url}...")

      case download(@spec_url) do
        {:ok, body} ->
          Mix.shell().info("  Downloaded #{byte_size(body)} bytes")
          {local_blocks, remote_blocks} = extract_cddl(body)

          local_content = Enum.join(local_blocks, "\n")
          remote_content = Enum.join(remote_blocks, "\n")

          File.write!(local_dest, local_content)
          File.write!(remote_dest, remote_content)

          Mix.shell().info(
            "  → #{local_dest} (#{byte_size(local_content)} bytes, #{length(local_blocks)} blocks)"
          )

          Mix.shell().info(
            "  → #{remote_dest} (#{byte_size(remote_content)} bytes, #{length(remote_blocks)} blocks)"
          )

        {:error, reason} ->
          Mix.shell().error("Failed to download spec: #{inspect(reason)}")
      end
    end
  end

  defp return_files(local, remote) do
    Mix.shell().info("  #{local}")
    Mix.shell().info("  #{remote}")
  end

  @doc false
  def extract_cddl(spec_content) do
    # The bikeshed source uses:
    #   <pre class="cddl" data-cddl-module="local-cddl">...</pre>
    #   <pre class="cddl" data-cddl-module="remote-cddl">...</pre>
    # Some blocks have both: data-cddl-module="local-cddl remote-cddl"
    #
    # Bikeshed (index.bs) uses slightly different syntax:
    #   <pre class="cddl local-cddl remote-cddl">
    # We handle both formats.

    regex = ~r/<pre[^>]*class="[^"]*cddl[^"]*"[^>]*>(.*?)<\/pre>/s

    Enum.reduce(Regex.scan(regex, spec_content), {[], []}, fn [full_match, content],
                                                              {local, remote} ->
      cleaned = clean_cddl(content)

      is_local = String.contains?(full_match, "local-cddl")
      is_remote = String.contains?(full_match, "remote-cddl")

      local = if is_local, do: [cleaned | local], else: local
      remote = if is_remote, do: [cleaned | remote], else: remote

      {local, remote}
    end)
    |> then(fn {local, remote} -> {Enum.reverse(local), Enum.reverse(remote)} end)
  end

  defp clean_cddl(content) do
    lines = String.split(content, "\n")

    # Calculate minimum leading whitespace (like the JS generate.js does)
    min_indent =
      lines
      |> Enum.reject(&(String.trim(&1) == ""))
      |> Enum.map(fn line ->
        case Regex.run(~r/^(\s+)/, line) do
          [_, spaces] -> String.length(spaces)
          nil -> 0
        end
      end)
      |> Enum.min(fn -> 0 end)

    lines
    |> Enum.map(fn line ->
      if String.length(line) > min_indent do
        String.slice(line, min_indent..-1//1)
      else
        String.trim(line)
      end
    end)
    |> Enum.join("\n")
    |> String.trim()
  end

  defp download(url) do
    url_charlist = String.to_charlist(url)

    http_opts = [
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      timeout: 60_000
    ]

    case :httpc.request(:get, {url_charlist, []}, http_opts, body_format: :binary) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        {:ok, body}

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
