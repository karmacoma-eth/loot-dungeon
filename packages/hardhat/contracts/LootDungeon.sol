pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; //https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol
import "@openzeppelin/contracts/utils/Address.sol";

// TODO: some kind of datastructure that abstracts whether we are dealing with real or synth loot
// making "enterWithSynth" and "enterWithReal" is getting old

// TODO: support for parties, i.e. canEnter(address[] player)
interface Dungeon {
    function name() pure external returns(string);

    function canEnter(address player) pure external returns(bool, string);

    // not responsible for checking the contract address or ownership
    // could use something like LootComponents.sol to check for specific attributes
    function canEnterWithRealLoot(address player, address contractAddress, uint tokenId) pure external returns(bool, string);

    // in seconds, so that we can use built-in Solidity time units
    function getTimeToComplete() pure external returns(uint);

    // returns [low, high] 
    function getXPReward() pure external returns(uint, uint);
}

// TODO: how can we support more types of rewards like resources? -> separate timelocking logic from accruing a rewards balance. That way, a dungeon can return a list of rewards or different reward kinds!
contract LootXP is Ownable {
    using Address for address;

    address constant LOOT_ADDRESS = 0xFF9C1b15B16263C61d017ee9F65C50e4AE0113D7;

    struct PendingXP {
        uint unlockTimestamp;
        uint reward;
    }

    // 12 first bytes are token id, last 20 bytes are address
    // e.g. can either refer to a specific Loot NFT (tokenId: 42, address: LOOT_ADDRESS)
    // or just a regular address, in which case we use the Synthetic Loot for that address
    mapping(uint => uint) accruedXP;

    mapping(uint => PendingXP) pendingXP;

    // initially just LOOT, but expandable
    mapping(address => bool) levelableContracts;

    // a dungeon is a contract that is allowed to timelock a player
    mapping(address => bool) approvedDungeons;

    constructor() {
        levelableContracts[LOOT_ADDRESS] = true;
    }

    function setContractLevelable(address contractAddress, bool levelable) external onlyOwner {
        require(contractAddress.isContract(), "contractAddress must be a contract");
        levelableContracts[contractAddress] = levelable;
    }

    function setDungeonContract(address contractAddress, bool approved) external onlyOwner {
        require(contractAddress.isContract(), "contractAddress must be a contract");
        approvedDungeons[contractAddress] = approved;
    }

    function enterDungeonWithSyntheticLoot(address player) external {
        require(approvedDungeons[msg.sender], "can only be called from a real Dungeon, for adventurers");
        require(Dungeon(msg.sender).canEnter(player), "player is not allowed to enter this dungeon");

        // TODO: double check if this makes sense. Maybe have the player call this directly instead, saying "I want to enter _this_ dungeon"
        require(player == tx.origin, "only player can enter itself");

        if (hasPendingRewards(player)) {
            require(pendingRewardsReady(player), "player is already adventuring");

            // collect the pending rewards
            PendingXP storage pendingForPlayer = pendingXP[player];
            accruedXP[player] += pendingForPlayer.reward;

            // and reset them
            pendingForPlayer.reward = 0;
            pendingForPlayer.unlockTimestamp = 0;
        }

        _enterDungeon(player, player, 0);
    }

    function hasPendingRewards(address player) public view returns(bool) {
        return pendingXP[player].unlockTimestamp != 0;
    }

    function pendingRewardsReady(address player) public view returns(bool) {
        return pendingXP[player].unlockTimestamp <= now;
    }

    function totalXP(address player) public view returns(uint) {
        if (hasPendingRewards(player) && pendingRewardsReady(player)) {
            return accruedXP[player] + pendingXP[player].reward;
        }

        return accruedXP[player];
    }

    function levelOf(address player) public view returns(uint) {
        uint xp = totalXP(player);
        if (xp > 355000) { return 20; }
        else if (xp > 305000) { return 19; }
        else if (xp > 265000) { return 18; }
        else if (xp > 225000) { return 17; }
        else if (xp > 195000) { return 16; }
        else if (xp > 165000) { return 15; }
        else if (xp > 140000) { return 14; }
        else if (xp > 120000) { return 13; }
        else if (xp > 100000) { return 12; }
        else if (xp > 85000) { return 11; }
        else if (xp > 64000) { return 10; }
        else if (xp > 48000) { return 9; }
        else if (xp > 34000) { return 8; }
        else if (xp > 23000) { return 7; }
        else if (xp > 14000) { return 6; }
        else if (xp > 6500) { return 5; }
        else if (xp > 2700) { return 4; }
        else if (xp > 900) { return 3; }
        else if (xp > 300) { return 2; }
        else { return 1; }
    }

    function enterDungeonWithRealLoot(address player, address levelable, uint tokenId) external {
        require(approvedDungeons[msg.sender], "can only be called from a real Dungeon, for adventurers");
        require(Dungeon(msg.sender).canEnterWithRealLoot(player, levelable, tokenId), "player is not allowed to enter this dungeon");

        require(levelableContracts[levelable], "not a levellable contract");
        require(ERC721(levelable).ownerOf(tokenId) == player, "player is not the owner of this Loot");
        
        // TODO: check for pending rewards for item

        _enterDungeon(player, player, 0);
    }
    
    function _enterDungeon(address player, address levelable, uint tokenId, Dungeon dungeon) internal {
        // TODO: deal with real item
        PendingXP storage pendingForPlayer = pendingXP[player];
        require(pendingForPlayer.unlockTimestamp == 0);
        
        pendingForPlayer.unlockTimestamp = dungeon.getTimeToComplete();

        // TODO: expandable kinds of rewards
        (uint low, uint high) = dungeon.getXPReward();
        pendingForPlayer.reward = somewhatRandomInRange(low, high);
    }

    function somewhatRandomInRange(uint low, uint high) internal view returns(uint) {
        return uint(keccak256(abi.encodePacked(now, msg.sender, block.blockhash(block.number - 1)))) % (high - low) + low;
    }
}


contract BasicLootDungeon is Ownable, Dungeon {
    function name() pure external returns(string) {
        return "Dungeon of noobing";
    }

    function canEnter(address player) pure external returns(bool, string) {
        return (true, "all are welcome");
    }

    function canEnterWithRealLoot(address player, address contractAddress, uint tokenId) pure external returns(bool, string) {
        return canEnter(player);
    }

    function getTimeToComplete() pure external returns(uint) {
        return 20 minutes;
    }

    function getXPReward() pure external returns(uint, uint) {
        return (100, 200);
    }
}


contract Level2LootDungeon is Ownable, Dungeon {
    LootXP lootxp;

    function init(address lootxpAddress) onlyOwner {
        lootxp = LootXP(lootxpAddress);
    }

    function name() pure external returns(string) {
        return "Dungeon of unremarkable dangers";
    }

    function canEnter(address player) pure external returns(bool, string) {
        return lootxp.levelOf(player) > 2;
    }

    function canEnterWithRealLoot(address player, address contractAddress, uint tokenId) pure external returns(bool, string) {
        return canEnter(player);
    }

    function getTimeToComplete() pure external returns(uint) {
        return 30 minutes;
    }

    function getXPReward() pure external returns(uint, uint) {
        return (150, 400);
    }
}