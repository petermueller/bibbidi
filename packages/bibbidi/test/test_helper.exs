:inets.start()
:ssl.start()

Mox.defmock(Bibbidi.MockConnection, for: Bibbidi.Connection)

ExUnit.start(exclude: [:integration])
