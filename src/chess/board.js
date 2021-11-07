export class Board {
    constructor() {
        this.squares = [
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
            [' ', ' ', ' ', ' ', ' ', ' ', ' ', ' '],
        ];
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

    square(position) {
        let [row, column] = positionToIndex(position);
        return this.squares[row][column];
    }

    setSquare(position, piece) {
        let [row, column] = positionToIndex(position);
        this.squares[row][column] = piece;
    }
}

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

const positionToIndex = (position) => {
    if (position.length != 2) {
        throw `Invalid position: ${position}`;
    }

    const row = Number(position[1]) - 1;
    const column = position.toLowerCase().charCodeAt(0) - 97;

    return [row, column];
}
