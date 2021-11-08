import { Piece } from '../chess/piece';
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

const Square = (props: SquareProps) => {
    if (props.data === null) {
        return null;
    } 

    switch ([props.data.color, props.data.type]) {
        case ['white', 'king']:
          return <img src={WhiteKing} className="piece" />;
        case ['white', 'queen']:
          return <img src={WhiteQueen} className="piece" />;
        case ['white', 'rook']:
          return <img src={WhiteRook} className="piece" />;
        case ['white', 'bishop']:
          return <img src={WhiteBishop} className="piece" />;
        case ['white', 'knight']:
          return <img src={WhiteKnight} className="piece" />;
        case ['white', 'pawn']:
          return <img src={WhitePawn} className="piece" />;
    
        case ['black', 'king']:
          return <img src={BlackKing} className="piece" />;
        case ['black', 'queen']:
          return <img src={BlackQueen} className="piece" />;
        case ['black', 'rook']:
          return <img src={BlackRook} className="piece" />;
        case ['black', 'bishop']:
          return <img src={BlackBishop} className="piece" />;
        case ['black', 'knight']:
          return <img src={BlackKnight} className="piece" />;
        case ['black', 'pawn']:
          return <img src={BlackPawn} className="piece" />;
        default:
            return null;
    }
}

type SquareProps = {
    data: Piece | null;
}

export default Square;
