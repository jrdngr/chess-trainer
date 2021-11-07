import { Board, Piece } from '../chess/board';
import './ChessBoard.css';

let board = Board.initialized();

const squareColor = (i: number, j: number) => {
    let white = j % 2 === 0;
    if (i % 2 === 1) {
        white = !white;
    }
    return white ? "white" : "black";
};

function ChessBoard() {
  return (
    <div className="board">
      {board.squares.reverse().map((row, i) => (
            <div className="row">
              {row.map((square, j) => (
                <span className={squareColor(i, j)}>{square}</span>
              ))}
        </div>

      ))}
    </div>
  );
}

export default ChessBoard;
