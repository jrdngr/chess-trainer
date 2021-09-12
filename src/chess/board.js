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
}

export const Piece = {
    WHITE_KING: '♔',
    WHITE_QUEEN: '♕',
    WHITE_ROOK: '♖',
    WHITE_BISHOP: '♗',
    WHITE_KNIGHT: '♘',
    WHITE_PAWN: '♙',

    BLACK_KING: '♚',
    BLACK_QUEEN: '♛',
    BLACK_ROOK: '♜',
    BLACK_BISHOP: '♝',
    BLACK_KNIGHT: '♞',
    BLACK_PAWN: '♟︎',
};

const positionToIndex = (position) => {
    if (position.length != 2) {
        throw `Invalid position: ${position}`;
    }

    const row = Number(position[1]) - 1;
    const column = position.toLowerCase().charCodeAt(0) - 97;

    return [row, column];
}
