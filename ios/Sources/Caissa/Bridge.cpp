// Caissa's search behind the C functions in include/caissa.h.

#include "caissa.h"

#include "backend/Evaluate.hpp"
#include "backend/Game.hpp"
#include "backend/Position.hpp"
#include "backend/Score.hpp"
#include "backend/Search.hpp"
#include "backend/TimeManager.hpp"
#include "backend/TranspositionTable.hpp"

#include <mutex>
#include <stdio.h>
#include <string.h>
#include <string>

void InitEngine();

struct CaissaSearcher
{
    TranspositionTable table;
    Search search;
};

static std::once_flag s_init;

static void InitOnce()
{
    std::call_once(s_init, [] { InitEngine(); });
}

bool caissa_load_network(const char* path)
{
    InitOnce();
    return LoadMainNeuralNetwork(path);
}

CaissaSearcher* caissa_create(uint32_t hashMegabytes)
{
    InitOnce();
    auto* searcher = new CaissaSearcher;
    searcher->table.Resize(size_t(hashMegabytes) * 1024 * 1024);
    return searcher;
}

void caissa_destroy(CaissaSearcher* searcher)
{
    delete searcher;
}

/// The lines as "<cp> <mate> <moves...>", one per line.
static std::string Write(const DynArray<PvLine>& lines)
{
    std::string out;
    for (uint32_t i = 0; i < lines.Size(); ++i)
    {
        const PvLine& line = lines[i];
        if (line.moves.Empty()) continue;
        const int32_t score = line.score;
        int32_t mate = 0;
        if (score > CheckmateValue - (int32_t)MaxSearchDepth) mate = (CheckmateValue - score + 1) / 2;
        else if (score < -CheckmateValue + (int32_t)MaxSearchDepth) mate = -((CheckmateValue + score + 1) / 2);
        char head[32];
        snprintf(head, sizeof(head), "%d %d", mate != 0 ? 0 : (int)NormalizeEval(score), (int)mate);
        out += head;
        for (uint32_t m = 0; m < line.moves.Size(); ++m)
        {
            out += ' ';
            out += line.moves[m].ToString().CStr();
        }
        out += '\n';
    }
    return out;
}

struct Progress
{
    CaissaProgress callback;
    void* context;
    uint32_t depth = 0;
};

static bool OnIteration(void* context, uint32_t depth, const DynArray<PvLine>& lines)
{
    Progress* progress = static_cast<Progress*>(context);
    progress->depth = depth;
    return progress->callback && progress->callback(progress->context, depth, Write(lines).c_str());
}

uint32_t caissa_search(
    CaissaSearcher* searcher, const char* fen, uint32_t maxDepth, uint32_t moveTimeMs, uint32_t multiPv,
    const char* searchmoves, CaissaProgress progress, void* context, char* out, uint32_t outSize, uint64_t* nodes)
{
    if (outSize > 0) out[0] = 0;
    if (nodes) *nodes = 0;

    Position position;
    if (!position.FromFEN(fen)) return 0;
    Game game;
    game.Reset(position);

    SearchParam param{ searcher->table };
    param.debugLog = false;
    param.useRootTablebase = false;
    param.numThreads = 1;
    param.numPvLines = multiPv > 0 ? multiPv : 1;
    param.limits.startTimePoint = TimePoint::GetCurrent();
    if (maxDepth > 0) param.limits.maxDepth = (uint16_t)(maxDepth < UINT8_MAX ? maxDepth : UINT8_MAX);
    if (moveTimeMs > 0)
    {
        TimeManagerInitData data;
        data.moveTime = (int32_t)moveTimeMs;
        data.remainingTime = INT32_MAX;
        data.timeIncrement = 0;
        data.theirRemainingTime = INT32_MAX;
        data.theirTimeIncrement = 0;
        data.movesToGo = UINT32_MAX;
        data.moveOverhead = 0;
        InitTimeManager(game, data, param.limits);
    }

    // searchmoves: every legal move is excluded except the ones named
    if (searchmoves && searchmoves[0])
    {
        MoveList legal;
        position.GetNumLegalMoves(&legal);
        std::string wanted = std::string(" ") + searchmoves + " ";
        for (uint32_t i = 0; i < legal.Size(); ++i)
        {
            const Move move = legal.GetMove(i);
            const std::string uci = std::string(" ") + move.ToString().CStr() + " ";
            if (wanted.find(uci) == std::string::npos) param.excludedMoves.PushBack(move);
        }
        if (param.excludedMoves.Size() == legal.Size()) return 0;
    }

    Progress state{ progress, context };
    param.onIteration = OnIteration;
    param.onIterationContext = &state;

    searcher->table.NextGeneration();
    SearchResult result;
    SearchStats stats;
    searcher->search.DoSearch(game, param, result, &stats);

    const std::string text = Write(result);
    if (outSize > 0)
    {
        const size_t n = text.size() < outSize - 1 ? text.size() : outSize - 1;
        memcpy(out, text.data(), n);
        out[n] = 0;
    }
    if (nodes) *nodes = stats.nodes;
    return state.depth;
}
