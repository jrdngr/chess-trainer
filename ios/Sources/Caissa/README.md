Caissa's search and evaluation (https://github.com/Witek902/Caissa, MIT, see
LICENSE), from upstream commit 395c2e6 (version 2.0.13): `src/backend`
without the Gaviota and Syzygy tablebase code. Its network is fetched at build
time, see `ios/scripts/fetch-caissa-net.sh`.

Changes from upstream, each marked "Chess Playbook" in the source:
- `Common.hpp`: architecture defines from the compiler instead of CMake;
  release settings; tablebases off (the app probes its own with Fathom).
- `Search.hpp`/`Search.cpp`: `SearchParam.onIteration`, called after each
  finished depth, which can stop the search.

`Bridge.cpp` and `include/caissa.h` are the C face Swift calls.
