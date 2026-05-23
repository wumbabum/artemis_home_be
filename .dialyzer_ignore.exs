[
  # Phoenix 1.8.3 + OTP 28 false positive in Phoenix.Router. The warning
  # appears at deps/phoenix/lib/phoenix/router.ex:1 with `pattern_match` —
  # a regex matches more reliably than the tuple form here.
  ~r/deps\/phoenix\/lib\/phoenix\/router\.ex.*pattern_match/
]
