# Tests tagged :yjs run the real Yjs on Node.js (see test/support/yjs.ex). They are
# skipped when Node.js or the npm packages are missing, unless YEX_REQUIRE_YJS is set
# (as on CI), which turns that into a failure instead.
exclude =
  case Yex.Yjs.check() do
    :ok ->
      []

    {:error, reason} ->
      if System.get_env("YEX_REQUIRE_YJS") in ["1", "true"] do
        raise "Yjs compatibility tests cannot run: #{reason}"
      end

      IO.puts("Skipping Yjs compatibility tests: #{reason}")
      [:yjs]
  end

ExUnit.start(exclude: exclude)
