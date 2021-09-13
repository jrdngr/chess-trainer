<script>
    import { Board, Piece } from '../chess/board';

    let board = Board.initialized();

    const squareColor = (i, j) => {
        let white = j % 2 === 0;
        if (i % 2 === 1) {
            white = !white;
        }
        return white ? "white" : "black";
    };
</script>

<div class="board">
    {#each board.squares.reverse() as row, i}
        <div class = "row">
            {#each row as square, j}
                <span class="{squareColor(i, j)}">{square}</span>
            {/each}
        </div>
    {/each}
</div>

<style>
    .board {
        display: flex;
        flex-direction: column;
        border: 1px solid black;
        font-size: 5em;
        text-align: center;
        width: 800px;
        height: 800px;
    }

    .row {
        display: flex;
        width: 100%;
        height: 100%;
    }

    .white {
        background: white;
        width: 100px;
        height: 100px;
    }

    .black {
        background: black;
        width: 100px;
        height: 100px;
    }
</style>
