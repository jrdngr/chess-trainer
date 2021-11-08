export class Piece {
    public color: PieceColor;
    public type: PieceType;

    constructor(color: PieceColor, type: PieceType) {
        this.color = color;
        this.type = type;
    }
}

export type PieceColor = 'white' | 'black';

export type PieceType = 'king' | 'queen' | 'rook' | 'bishop' | 'knight' | 'pawn';
