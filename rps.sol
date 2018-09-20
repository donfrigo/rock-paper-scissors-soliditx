pragma solidity 0.4.24;

import "github.com/OpenZeppelin/zeppelin-solidity/contracts/math/SafeMath.sol";

/* Rules
1, Rock beats scissors, scissors beats paper, paper beats rock.
2, A game starts when the first player joins.
3, The game should be fair, so neither player should have an advantage over the other.
4, A cheating player should always lose.
5, The winner of the game should be enshrined forever in the smart contract before the game is reset.
6, Players should have an incentive not to cheat.
*/

// choiceCodes: 0: Rock, 1: Paper, 2: Scissors

// Players can register by sending a choiceCode, a random number and their bet using the register function
// If only one player is registered, she can abandon the game using the abandonGame function, which refunds her and resets the game
// If two players have registered, they have one hour to reveal their votes otherwise, both of their funds are lost
// If one of the players reveals her bet, the other player has 3 minutes to reveal her bet as well, otherwise the other player takes all
// At the end of the game, function endGame can be called, which takes care of sending the funds to the players and resets the game

contract rps {
    
    using SafeMath for uint256;
    
    bool public inProgress; // whether game is in progress
    address[] public winnersArray; // used to store addresses of winners
    mapping (uint256 => mapping(uint256 => uint256)) internal rulesMatrix; // array to store rules of game
    uint256 public minimumBet = 10000; // smallest amount of bet in Wei
   
    // structure to store player data
    struct Player {
        address playerAddress;
        uint256 choiceCode;
        bytes32 hashChoice;
        bool revealed;
    }
    
    // structure to store game data
    struct Game {
        Player player1;
        Player player2;
        uint256 status;
        uint256 revealDeadline;
        uint256 gameDeadline;
    }
    
    // game instance
    Game game;
    
    // initialize the game rules
    constructor() public{
        rulesMatrix[0][0] = 0;
        rulesMatrix[0][1] = 2;
        rulesMatrix[0][2] = 1;
        rulesMatrix[1][0] = 1;
        rulesMatrix[1][1] = 0;
        rulesMatrix[1][2] = 2;
        rulesMatrix[2][0] = 2;
        rulesMatrix[2][1] = 1;
        rulesMatrix[2][2] = 0;
    }
    
    /**
    * @dev  modifier that checks whether bet is larger, than minimumBet.
    */
    modifier isBetEnough() {
        require(msg.value >= minimumBet, "Bet must be larger or equal to minimumBet!");
        _;
    }
    
    /**
    * @dev  modifier that checks whether given choiceCode is valid or not.
    * @param _choiceCode rock(0), paper(1) or scissors (3).
    */
     modifier isValidChoice (uint256 _choiceCode) {
        require (_choiceCode >= 0 && _choiceCode <= 2, "Valid choice must be provided!");
       _;
    }
    
    /**
    * @dev calculates hash to be stored as commitment.
    * @param _choiceCode rock(0), paper(1) or scissors (3).
    * @param _randomNumber random number used to create a unique hash 
    */
    function calculateHash (uint256 _choiceCode, uint256 _randomNumber) internal pure returns (bytes32){
        return keccak256(abi.encodePacked(keccak256(abi.encodePacked(_choiceCode)) ^ keccak256(abi.encodePacked(_randomNumber))));
    }
 
    /**
    * @dev returns winner based on input.
    * @param _choicePlayer1 rock(0), paper(1) or scissors (3).
    * @param _choicePlayer2 rock(0), paper(1) or scissors (3).
    */
    function getWinner (uint256 _choicePlayer1, uint256 _choicePlayer2) internal view returns (uint256) {
        return rulesMatrix[_choicePlayer1][_choicePlayer2];
    }
 
    /**
    * @dev registers new players.
    * @param _choiceCode rock(0), paper(1) or scissors (3).
    * @param _randomNumber random number used to create a unique hash 
    */
    function register(uint256 _choiceCode, uint256 _randomNumber) public payable isBetEnough() isValidChoice(_choiceCode) {
        // if game hasn't started yet
        if (!inProgress){
            // start game
            game.player1.playerAddress = msg.sender;
            game.player1.hashChoice = calculateHash(_choiceCode,_randomNumber);
           
            game.status = 1; // first player registered
            inProgress = true; // game started
        } else if (game.status == 1) {
            // second player registering
            // second player cannot be the same as player player 1
            require(game.player1.playerAddress != msg.sender, "Second player cannot be the same as player player 1");
             
            game.player2.playerAddress = msg.sender;
            game.player2.hashChoice = calculateHash(_choiceCode,_randomNumber);
            game.status = 2; // two players have registered
            game.gameDeadline = now.add(1 hours); // players have 1 hours to reveal, if not, both of their funds are burnt
        }
    }
    
    /**
    * @dev players can reveal their previously committed vote.
    * @param _choiceCode rock(0), paper(1) or scissors (3).
    * @param _randomNumber random number used to create a unique hash.
    */
    function reveal (uint256 _choiceCode, uint256 _randomNumber) public {
        // if two players have registered or reveal phase has already started
        require(game.status >= 2, "Two players must be present");
        if (msg.sender == game.player1.playerAddress) {
            // player 1
            
            require(calculateHash(_choiceCode,_randomNumber) == game.player1.hashChoice,"Previously committed values must be provided");
            game.player1.choiceCode = _choiceCode;
            game.player1.revealed = true;
            
            // if deadline is not set
            if (game.revealDeadline == 0){
                // other player has 180 seconds
                game.revealDeadline = now.add(180);
                game.status = 3; // reveal phase
            }
        } else if (msg.sender == game.player2.playerAddress) {
            // player 2
            
            require(calculateHash(_choiceCode,_randomNumber) == game.player2.hashChoice,"Previously committed values must be provided");
            game.player2.choiceCode = _choiceCode;
            game.player2.revealed = true;
            
             // if deadline is not set
            if (game.revealDeadline == 0){
                // other player has 180 seconds
                game.revealDeadline = now.add(180);
                game.status = 3; // reveal phase
            }
        }
    }
    
    /**
    * @dev game can be ended if:
    * both players have revealed their votes OR
    * only one of the players has revealed her vote before the revealDeadline OR
    * none of the players have revealed their votes before the gameDeadline.
    */
    function endGame() public{
        // if game is still in progress
        require(inProgress, "Game must be in progress to end it");
        address winnerAddress;
        if (game.player1.revealed && game.player2.revealed) {
            // if both players have revealed   
            // select winner
            bool draw;
            uint256 winner = getWinner(game.player1.choiceCode,game.player2.choiceCode);
            if (winner == 1) {
                winnerAddress = game.player1.playerAddress;
            } else if (winner == 2){
                winnerAddress = game.player2.playerAddress;
            } else {
            // draw
            draw = true;
            }
            
            if (draw){
                // save addresses, so that internal state is updated before interacting with other contracts
                address address1 = game.player1.playerAddress;
                address address2 = game.player2.playerAddress;
                
                // end game
                inProgress = false;
                // reset game
                delete game;
                
                address1.transfer(address(this).balance.div(2));
                address2.transfer(address(this).balance);
            } else {
                
                // add to winners' array
                winnersArray.push(winnerAddress);
                    
                // end game
                inProgress = false;
                // reset game
                delete game;
                
                winnerAddress.transfer(address(this).balance);
            }
           
            
        } else if (now > game.revealDeadline && game.status == 3) {
            
            // if only one player has revealed, she takes all
            if (game.player1.revealed) {
                winnerAddress = game.player1.playerAddress;
            } else if (game.player2.revealed){
                winnerAddress = game.player2.playerAddress;
            } 
            
            // end game
            inProgress = false;
            // reset game
            delete game;
            // add to winners' array
            winnersArray.push(winnerAddress);
            
            winnerAddress.transfer(address(this).balance);
            
        } else if (now > game.gameDeadline){
                // if none has revealed, money is burnt
                // reset game
                inProgress = false;
                delete game;
                address(0).transfer(address(this).balance);
        }
        require(!inProgress, "It is not possible to end the game yet");
    }
 
    /**
    * @dev player 1 can leave the game if no other players are present.
    */
    function abandonGame () public{
        // if only one player is present
        require (game.status == 1);
        // sender is player one
        if (msg.sender == game.player1.playerAddress) {
           // reset game
           inProgress = false;
           delete game;
           address(msg.sender).transfer(address(this).balance);
        }
    }
   
}
