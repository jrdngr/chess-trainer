#pragma once

// A C face for Caissa's search, so Swift can call it.

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CaissaSearcher CaissaSearcher;

/// Told after each finished depth, with the lines as `caissa_search` writes them.
/// Returning true stops the search there.
typedef bool (*CaissaProgress)(void* context, uint32_t depth, const char* lines);

/// Load the network from a .pnn file. Call once before any search; false if it can't be read.
bool caissa_load_network(const char* path);

/// A searcher with its own transposition table of `hashMegabytes`.
CaissaSearcher* caissa_create(uint32_t hashMegabytes);
void caissa_destroy(CaissaSearcher* searcher);

/// Search a position. `maxDepth` 0 and `moveTimeMs` 0 mean no limit of that kind.
/// `searchmoves` is UCI moves separated by spaces, or NULL for every move.
/// Writes one line per PV into `out`: "<cp> <mate> <move> <move>...", the score
/// for the side to move in centipawns and mate in moves (0 for none, negative
/// when getting mated). Returns the deepest finished depth.
uint32_t caissa_search(
  CaissaSearcher* searcher, const char* fen, uint32_t maxDepth, uint32_t moveTimeMs, uint32_t multiPv,
  const char* searchmoves, CaissaProgress progress, void* context, char* out, uint32_t outSize, uint64_t* nodes);

#ifdef __cplusplus
}
#endif
