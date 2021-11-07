import { useState } from 'react';
import { Board } from '../chess/board';
import './ChessBoard.css';
import Piece from './Piece';

function ChessBoard() {
  let [board, setBoard] = useState(Board.initialized());

  const squareColor = (i: number, j: number) => {
      let white = j % 2 === 0;
      if (i % 2 === 1) {
          white = !white;
      }
      return white ? "white" : "black";
  };

  return (
    <div className="board">
      {board.squares.reverse().map((row, i) => (
            <div className="row">
              {row.map((square, j) => (
                <span className={squareColor(i, j)}>
                  <Piece type={square} />
                </span>
              ))}
        </div>
      ))}
    </div>
  );
}

export default ChessBoard;
