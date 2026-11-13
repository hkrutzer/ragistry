import Config

config :logger, level: :warning

config :ra,
  data_dir:
    System.get_env("RAGISTRY_TEST_DATA_DIR", Path.expand("../tmp/ra", __DIR__))
    |> String.to_charlist()
