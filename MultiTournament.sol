// SPDX-License-Identifier: MIT

pragma solidity ^0.8.11;

import "./ownable.sol";

/// @title A multi-player tournament contract for Unity game
/// @author Kyle Szostek
/// @notice This contracts allow multiple instances of game to run at the same time.  
/// @dev All functions are tested and working successfully, some have HUGE security issues.

contract MultiTournament is Ownable{

    enum Result{none, created, active, abandoned}

    struct Game {
        address payable[] players;
        uint entryFee;
        uint pot;
        Result result;
        uint timeStamp;
    }

    mapping(uint => Game) games;
    uint private numberOfGames;
    uint timeout = 300;
  
    event NewGameCreated(uint gameId, address creator, uint timeStamp);

    event PlayerJoinedGame(uint gameId, address joinee, uint timeStamp);

    event GameEnded(uint gameId, Result result, uint timeStamp);

    modifier hasValue() {
        require(msg.value > 0, "Ether required");
        _;
    }
  
    modifier gameExists(uint _gameId){
        require(_gameId <= numberOfGames, "Invalid Game Id, No such game exists");
        _;
    }
  
    modifier isGameActive(uint _gameId){
        require(games[_gameId].result == Result.active, "Game is no longer Active");
        _;
    }

    modifier isGameCreated(uint _gameId){
        require(games[_gameId].result == Result.created, "Game is no longer available");
        _;
    }
  
    ///  Allows players to create a new game
    ///  new game is generated and values are initialized
    ///  the ID of the game is returned
    function newGame() external payable hasValue returns(uint) {
        ++numberOfGames;
        uint gameId = numberOfGames;
        games[gameId].players.push(payable(msg.sender));
        games[gameId].entryFee = msg.value;
        games[gameId].pot = msg.value;
        games[gameId].result = Result.created;
        games[gameId].timeStamp = block.timestamp;
        emit NewGameCreated(gameId, msg.sender, games[gameId].timeStamp);
        // Store gameId on photon, to reference later when game is won or needs to be refunded:
        return gameId;
    }

    ///  Allows playes to join game already created by someone else
    ///  _gameId ID of the game which is to be joined
    ///  success True on successful execution. Else the transaction is reverted.
    function joinGame(uint _gameId) external payable hasValue gameExists(_gameId) isGameCreated(_gameId) returns(bool success){
        require(msg.value == games[_gameId].entryFee, "Invalid amount of Ether sent");
        
        Game storage game = games[_gameId];

        game.players.push(payable(msg.sender));
        game.pot += msg.value;
        game.timeStamp = block.timestamp;

        emit PlayerJoinedGame(_gameId, msg.sender, game.timeStamp);

        return true;
    }


    // When match creator clicks Start Match button in-game, match is set to active
    // Match creator cannot call Refund function after setGameActive is called
    function setGameActive(uint _gameId) external gameExists(_gameId) isGameCreated(_gameId) returns (bool success) {
        games[_gameId].result = Result.active;
        return true;
    }

    // Winner can only claim reward within 5 minutes after match is complete
    // NOT SECURE. It allows anyone to claim reward. Consider revising.
    function claimReward(uint _gameId, address payable _winner) external gameExists(_gameId) isGameActive(_gameId) returns (bool success){
        require(block.timestamp - games[_gameId].timeStamp <= timeout, "Cannot claim reward after 5 minutes of inactivity");
        
        Game storage game = games[_gameId];
        _winner.transfer(game.pot);
        game.result = Result.abandoned;
        game.timeStamp = block.timestamp;
        game.pot = 0;
        emit GameEnded(_gameId, game.result, game.timeStamp);
        return true;
    }
  
  // Player 0 in match will be shown button to claim reward if tied. Player 1 will automatically receive reward
    function claimRewardIfTied(uint _gameId, address payable _firstPlacePlayer, address payable _secondPlacePlayer) external gameExists(_gameId) isGameActive(_gameId) returns (bool success){
        require(block.timestamp - games[_gameId].timeStamp <= timeout, "Cannot claim reward after 5 minutes of inactivity");
        
        Game storage game = games[_gameId];
        _firstPlacePlayer.transfer(game.pot / 2);
        _secondPlacePlayer.transfer(game.pot / 2);
        game.result = Result.abandoned;
        game.timeStamp = block.timestamp;
        game.pot = 0;
        emit GameEnded(_gameId, game.result, game.timeStamp);
        return true;
    }

    // if match is created, but hasn't started yet, game owner can cancel match, and all entry fee's are sent back to joined players:
    function claimRefund(uint _gameId) external gameExists(_gameId) returns(bool success){
        require(games[_gameId].result != Result.active, "Game has started, cannot claim refund.");
        require(games[_gameId].result == Result.created, "Game is in-progress, cannot claim refund.");
        Game storage game = games[_gameId];
        for (uint i=0; i<game.players.length; i++) {
            game.players[i].transfer(game.entryFee);
        }
        game.result = Result.abandoned;
        game.timeStamp = block.timestamp;
        game.pot = 0;
        emit GameEnded(_gameId, game.result, game.timeStamp);
        return true;
    }

    // If pot hasn't been claimed after 5 minutes, send pot to my dev address for further dispute
    // NOT SECURE
    function unclaimedPot(uint _gameId, address payable _devAddress) external gameExists(_gameId) isGameActive(_gameId) returns(bool success) {
        Game storage game = games[_gameId];
        _devAddress.transfer(game.pot);
        game.result = Result.abandoned;
        game.timeStamp = block.timestamp;
        game.pot = 0;
        emit GameEnded(_gameId, game.result, game.timeStamp);
        return true;
    }

    // Gets the number of games that have been created
    function getNumberOfGames() external view returns(uint){
        return numberOfGames;
    }

    function getNumberOfPlayersInMatch(uint _gameId) external view returns (uint) {
        return games[_gameId].players.length;
    }

    function getBalanceOfPot(uint _gameId) external view returns (uint) {
        return games[_gameId].pot;
    }

    // Timer counts down on the winner screen. If 5 minutes passes, status is checked.
    // If status is still active, send pot to dev address
    function isGameStillActive(uint _gameId) external view returns (bool success) {
        require(games[_gameId].result == Result.active, "Game is no longer active.");
        return true;
    }
  
}
