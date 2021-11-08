import { Piece } from "./piece";

export class Board {
    private squares: Square[][];

    constructor() {
        this.squares = [];
    }

    static initialized() {
        const board = new Board
        board.squares = [
            ['♖', '♘', '♗', '♕', '♔', '♗', '♘', '♖'],
            ['♙', '♙', '♙', '♙', '♙', '♙', '♙', '♙'],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            ['♟︎', '♟︎', '♟︎', '♟︎', '♟︎', '♟︎', '♟︎', '♟︎'],
            ['♜', '♞', '♝', '♛', '♚', '♝', '♞', '♜'],
        ];

        return board;
    }

    square(position: Position) {
        let [row, column] = positionToIndex(position);
        return this.squares[row][column];
    }

    setSquare(position: Position, piece: Piece | Empty) {
        let [row, column] = positionToIndex(position);
        this.squares[row][column] = piece;
    }
}

export type File = "A" | "B" | "C" | "D" | "E" | "F" | "H" | "G";
export type Rank = "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8";
export type Position = `${File}${Rank}`;

export type Empty = null;
export type Square = Piece | Empty;

export const PieceType = {
    WHITE_KING: 0,
    WHITE_QUEEN: 1,
    WHITE_ROOK: 2,
    WHITE_BISHOP: 3,
    WHITE_KNIGHT: 4,
    WHITE_PAWN: 5,

    BLACK_KING: 6,
    BLACK_QUEEN: 7,
    BLACK_ROOK: 8,
    BLACK_BISHOP: 9,
    BLACK_KNIGHT: 10,
    BLACK_PAWN: 11,
};

const positionToIndex = (position: Position) => {
    const row = Number(position[1]) - 1;
    const column = position.toLowerCase().charCodeAt(0) - 97;

    return [row, column];
}
