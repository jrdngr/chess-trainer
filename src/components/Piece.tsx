import { PieceType } from '../chess/board';
import BlackBishop from '../images/pieces/black-bishop.svg';
import BlackKing from '../images/pieces/black-king.svg';
import BlackKnight from '../images/pieces/black-knight.svg';
import BlackPawn from '../images/pieces/black-pawn.svg';
import BlackQueen from '../images/pieces/black-queen.svg';
import BlackRook from '../images/pieces/black-rook.svg';
import WhiteBishop from '../images/pieces/white-bishop.svg';
import WhiteKing from '../images/pieces/white-king.svg';
import WhiteKnight from '../images/pieces/white-knight.svg';
import WhitePawn from '../images/pieces/white-pawn.svg';
import WhiteQueen from '../images/pieces/white-queen.svg';
import WhiteRook from '../images/pieces/white-rook.svg';

const Piece = (props: any) => {
    switch (props.type) {
        case PieceType.WHITE_KING:
          return <img src={WhiteKing} className="piece" />;
        case PieceType.WHITE_QUEEN:
          return <img src={WhiteQueen} className="piece" />;
        case PieceType.WHITE_ROOK:
          return <img src={WhiteRook} className="piece" />;
        case PieceType.WHITE_BISHOP:
          return <img src={WhiteBishop} className="piece" />;
        case PieceType.WHITE_KNIGHT:
          return <img src={WhiteKnight} className="piece" />;
        case PieceType.WHITE_PAWN:
          return <img src={WhitePawn} className="piece" />;
    
        case PieceType.BLACK_KING:
          return <img src={BlackKing} className="piece" />;
        case PieceType.BLACK_QUEEN:
          return <img src={BlackQueen} className="piece" />;
        case PieceType.BLACK_ROOK:
          return <img src={BlackRook} className="piece" />;
        case PieceType.BLACK_BISHOP:
          return <img src={BlackBishop} className="piece" />;
        case PieceType.BLACK_KNIGHT:
          return <img src={BlackKnight} className="piece" />;
        case PieceType.BLACK_PAWN:
          return <img src={BlackPawn} className="piece" />;
        default:
            return null;
    }
}

export default Piece;
