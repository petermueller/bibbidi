defmodule Bibbidi.Commands.Emulation do
  @moduledoc """
  Command builders for the `emulation` module of the WebDriver BiDi protocol.
  """

  alias Bibbidi.Connection

  @doc """
  Sets the forced colors mode theme override.

  `theme` is `"light"`, `"dark"`, or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_forced_colors_mode_theme_override(GenServer.server(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_forced_colors_mode_theme_override(conn, theme, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetForcedColorsModeThemeOverride{
      theme: theme,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the geolocation override.

  `coordinates_or_error` is either a coordinates map (e.g. `%{latitude: 37.7, longitude: -122.4}`),
  `nil` to reset, or an error map (e.g. `%{type: "positionUnavailable"}`).

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_geolocation_override(GenServer.server(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_geolocation_override(conn, coordinates_or_error, opts \\ []) do
    params =
      case coordinates_or_error do
        %{type: "positionUnavailable"} -> %{error: coordinates_or_error}
        other -> %{coordinates: other}
      end

    params =
      params
      |> then(fn p -> if opts[:contexts], do: Map.put(p, :contexts, opts[:contexts]), else: p end)
      |> then(fn p ->
        if opts[:user_contexts], do: Map.put(p, :userContexts, opts[:user_contexts]), else: p
      end)

    Connection.send_command(conn, "emulation.setGeolocationOverride", params)
  end

  @doc """
  Sets the locale override.

  `locale` is a locale string (e.g. `"en-US"`) or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_locale_override(GenServer.server(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_locale_override(conn, locale, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetLocaleOverride{
      locale: locale,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets network condition overrides.

  `network_conditions` is a conditions map (e.g. `%{type: "offline"}`) or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_network_conditions(GenServer.server(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_network_conditions(conn, network_conditions, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetNetworkConditions{
      network_conditions: network_conditions,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the screen orientation override.

  `screen_orientation` is an orientation map (e.g.
  `%{natural: "portrait", type: "portrait-primary"}`) or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_screen_orientation_override(GenServer.server(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_screen_orientation_override(conn, screen_orientation, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetScreenOrientationOverride{
      screen_orientation: screen_orientation,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the screen settings override.

  `screen_area` is a screen area map (e.g. `%{width: 1920, height: 1080}`) or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_screen_settings_override(GenServer.server(), map() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_screen_settings_override(conn, screen_area, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetScreenSettingsOverride{
      screen_area: screen_area,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Enables or disables scripting.

  `enabled` is `false` to disable scripting or `nil` to reset to default.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_scripting_enabled(GenServer.server(), false | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_scripting_enabled(conn, enabled, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetScriptingEnabled{
      enabled: enabled,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the scrollbar type override.

  `scrollbar_type` is `"classic"`, `"overlay"`, or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_scrollbar_type_override(GenServer.server(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_scrollbar_type_override(conn, scrollbar_type, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetScrollbarTypeOverride{
      scrollbar_type: scrollbar_type,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the timezone override.

  `timezone` is an IANA timezone string (e.g. `"America/New_York"`) or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_timezone_override(GenServer.server(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_timezone_override(conn, timezone, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetTimezoneOverride{
      timezone: timezone,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the touch override.

  `max_touch_points` is a positive integer or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_touch_override(GenServer.server(), pos_integer() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_touch_override(conn, max_touch_points, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetTouchOverride{
      max_touch_points: max_touch_points,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end

  @doc """
  Sets the user agent override.

  `user_agent` is a user agent string or `nil` to reset.

  ## Options

  - `:contexts` - List of browsing context IDs to scope the override.
  - `:user_contexts` - List of user context IDs to scope the override.
  """
  @spec set_user_agent_override(GenServer.server(), String.t() | nil, keyword()) ::
          {:ok, map()} | {:error, term()}
  def set_user_agent_override(conn, user_agent, opts \\ []) do
    Connection.execute(conn, %__MODULE__.SetUserAgentOverride{
      user_agent: user_agent,
      contexts: opts[:contexts],
      user_contexts: opts[:user_contexts]
    })
  end
end
