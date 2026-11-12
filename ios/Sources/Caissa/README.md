Caissa's search and evaluation (https://github.com/Witek902/Caissa, MIT, see
LICENSE), from upstream commit 7941009 (version 2.0.15): `src/backend`
without the Gaviota and Syzygy tablebase code. Its network is in
`Sources/Engine/CaissaNet`.

Changes from upstream, each marked "Chess Playbook" in the source:
- `Common.hpp`: architecture defines from the compiler instead of CMake;
  release settings; tablebases off (the app probes its own with Fathom).
- `Search.hpp`/`Search.cpp`: `SearchParam.onIteration`, called after each
  finished depth, which can stop the search.

`Bridge.cpp` and `include/caissa.h` are the C face Swift calls.
