import { Piece } from "./piece";

export class Board {
    public squares: Square[][];

    constructor() {
        this.squares = [];
        for(let i = 0; i < 8; i++) {
            let row = [];
            for (let j = 0; i < 8; j++) {
                row.push(null);
            }
        }
    }

    static initialized() {
        const board = new Board();

        // White
        board.setSquare("A1", new Piece('white', 'rook'));
        board.setSquare("B1", new Piece('white', 'knight'));
        board.setSquare("C1", new Piece('white', 'bishop'));
        board.setSquare("D1", new Piece('white', 'queen'));
        board.setSquare("E1", new Piece('white', 'king'));
        board.setSquare("F1", new Piece('white', 'bishop'));
        board.setSquare("G1", new Piece('white', 'knight'));
        board.setSquare("H1", new Piece('white', 'rook'));

        board.setSquare("A2", new Piece('white', 'pawn'));
        board.setSquare("B2", new Piece('white', 'pawn'));
        board.setSquare("C2", new Piece('white', 'pawn'));
        board.setSquare("D2", new Piece('white', 'pawn'));
        board.setSquare("E2", new Piece('white', 'pawn'));
        board.setSquare("F2", new Piece('white', 'pawn'));
        board.setSquare("G2", new Piece('white', 'pawn'));
        board.setSquare("H2", new Piece('white', 'pawn'));

        // Black
        board.setSquare("A8", new Piece('black', 'rook'));
        board.setSquare("B8", new Piece('black', 'knight'));
        board.setSquare("C8", new Piece('black', 'bishop'));
        board.setSquare("D8", new Piece('black', 'queen'));
        board.setSquare("E8", new Piece('black', 'king'));
        board.setSquare("F8", new Piece('black', 'bishop'));
        board.setSquare("G8", new Piece('black', 'knight'));
        board.setSquare("H8", new Piece('black', 'rook'));

        board.setSquare("A7", new Piece('black', 'pawn'));
        board.setSquare("B7", new Piece('black', 'pawn'));
        board.setSquare("C7", new Piece('black', 'pawn'));
        board.setSquare("D7", new Piece('black', 'pawn'));
        board.setSquare("E7", new Piece('black', 'pawn'));
        board.setSquare("F7", new Piece('black', 'pawn'));
        board.setSquare("G7", new Piece('black', 'pawn'));
        board.setSquare("H7", new Piece('black', 'pawn'));

        return board;
    }

    square(position: Position) {
        let [row, column] = positionToIndex(position);
        return this.squares[row][column];
    }

    setSquare(position: Position, piece: Piece | null) {
        let [row, column] = positionToIndex(position);
        this.squares[row][column] = piece;
    }
}

export type File = "A" | "B" | "C" | "D" | "E" | "F" | "G" | "H";
export type Rank = "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8";
export type Position = `${File}${Rank}`;

export type Square = Piece | null;

const positionToIndex = (position: Position) => {
    const row = Number(position[1]) - 1;
    const column = position.toLowerCase().charCodeAt(0) - 97;

    return [row, column];
}
