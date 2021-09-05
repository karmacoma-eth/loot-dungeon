pragma solidity >=0.8.0 <0.9.0;
//SPDX-License-Identifier: MIT

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol"; //https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol
import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";


// data structure that abstracts whether we are dealing with real or synth loot
struct Player {
    address walletAddress;
    address contractAddress;
    uint tokenId;
}


struct PendingReward {
    uint unlockTimestamp;
    address rewardContract;
    uint minAmount;
    uint maxAmount;
}


library PlayerFunctions {
    function isSynthetic(Player memory player) internal pure returns(bool) {
        return player.contractAddress == address(0);
    }

    function isValid(Player memory player) internal view returns(bool) {
        return isSynthetic(player) || IERC721(player.contractAddress).ownerOf(player.tokenId) == player.walletAddress;
    }

    function toCompactForm(Player memory player) internal pure returns(uint) {
        if (isSynthetic(player)) {
            return uint(uint160(player.walletAddress));
        }

        return uint(player.tokenId << 160) | uint(uint160(player.contractAddress));
    }

    function owner(Player memory player) internal view returns(address) {
        if (isSynthetic(player)) {
            return player.walletAddress;
        }

        return IERC721(player.contractAddress).ownerOf(player.tokenId);
    }
}


// TODO: chance of success
// TODO: support for parties, i.e. canEnter(address[] player)
interface Adventure {
    function name() pure external returns(string memory);

    function canEnter(Player calldata player) view external returns(bool, string memory);

    // in seconds, so that we can use built-in Solidity time units
    function getTimeToComplete() view external returns(uint);

    function getReward(Player calldata player) view external returns(PendingReward memory);
}


interface Reward {
    function name() pure external returns(string memory);
    function accrue(Player calldata player, uint amount) external;
    function balance(Player calldata player) external returns(uint);
}


contract AdventureRegistry is Ownable {
    address constant LOOT_ADDRESS = 0xFF9C1b15B16263C61d017ee9F65C50e4AE0113D7;
    address constant MORE_LOOT_ADDRESS = 0x1dfe7Ca09e99d10835Bf73044a23B73Fc20623DF;

    using Address for address;
    using PlayerFunctions for Player;
    
    // initially just loot and mloot, but expandable
    mapping(address => bool) levelableContracts;

    // an adventure is a contract that is allowed to timelock a player
    mapping(address => bool) adventures;

    // a reward is some balance that can be increased by completing adventures
    mapping(address => bool) rewards;

    mapping(uint => PendingReward) pending;

    event RewardsCollected(address collector, Player player, address rewardContract, uint amount);
    event AdventureStarted(address adventureStarter, Player player, Adventure adventure, PendingReward pendingReward);

    constructor() {
        levelableContracts[LOOT_ADDRESS] = true;
        levelableContracts[MORE_LOOT_ADDRESS] = true;
    }

    function setLevelable(address contractAddress, bool levelable) external onlyOwner {
        require(contractAddress.isContract(), "contractAddress must be a contract");
        levelableContracts[contractAddress] = levelable;
    }

    function setAdventure(address contractAddress, bool approved) external onlyOwner {
        require(contractAddress.isContract(), "contractAddress must be a contract");
        adventures[contractAddress] = approved;
    }

    function setRewards(address contractAddress, bool approved) external onlyOwner {
        require(contractAddress.isContract(), "contractAddress must be a contract");
        rewards[contractAddress] = approved;
    }

    function hasPendingRewards(Player memory player) public view returns(bool) {
        return pending[player.toCompactForm()].unlockTimestamp != 0;
    }

    function pendingRewardsReady(Player memory player) public view returns(bool) {
        return pending[player.toCompactForm()].unlockTimestamp <= block.timestamp;
    }

    // note: anybody can collect rewards on behalf of a player (why not?)
    function collectPendingRewards(Player memory player) public {
        require(hasPendingRewards(player), "player has no pending rewards");
        require(pendingRewardsReady(player), "rewards are not ready to be collected");

        PendingReward storage pendingReward = pending[player.toCompactForm()];
        uint rewardAmount = somewhatRandomInRange(pendingReward.minAmount, pendingReward.maxAmount);

        Reward(pendingReward.rewardContract).accrue(player, rewardAmount);

        emit RewardsCollected(msg.sender, player, pendingReward.rewardContract, rewardAmount);

        pendingReward.unlockTimestamp = 0;
        pendingReward.rewardContract = address(0);
        pendingReward.minAmount = 0;
        pendingReward.maxAmount = 0;
    }

    function startAdventure(Player memory player, Adventure adventure) external {
        require(adventures[address(adventure)], "can only be called from a real Adventure, for adventurers");

        (bool canEnter, string memory reason) = adventure.canEnter(player);
        require(canEnter, reason);

        require(player.isValid());
        require(player.owner() == msg.sender, "msg.sender must be the owner of this player");

        require(levelableContracts[player.contractAddress], "not a levelable contract");

        if (hasPendingRewards(player)) {
            require(pendingRewardsReady(player), "player is already in an adventure");

            collectPendingRewards(player);
        }

        require(pending[player.toCompactForm()].unlockTimestamp == 0);

        // copy to storage
        pending[player.toCompactForm()] = adventure.getReward(player);

        emit AdventureStarted(msg.sender, player, adventure, pending[player.toCompactForm()]);
    }

    function somewhatRandomInRange(uint low, uint high) internal view returns(uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, blockhash(block.number - 1)))) % (high - low) + low;
    }
}


// XP is a non-transferable reward
contract Experience is Ownable, Reward {
    using PlayerFunctions for Player;

    // 12 first bytes are token id, last 20 bytes are address
    // e.g. can either refer to a specific Loot NFT (tokenId: 42, address: LOOT_ADDRESS)
    // or just a regular address, in which case we use the Synthetic Loot for that address
    mapping(uint => uint) accruedXP;

    AdventureRegistry registry;

    function init(address registryAddress) external onlyOwner  {
        registry = AdventureRegistry(registryAddress);
    }

    function levelOf(Player calldata player) public view returns(uint) {
        uint xp = accruedXP[player.toCompactForm()];
        if (xp > 4428675) { return 20; }
        else if (xp > 2952450) { return 19; }
        else if (xp > 1968300) { return 18; }
        else if (xp > 1312200) { return 17; }
        else if (xp > 874800) { return 16; }
        else if (xp > 583200) { return 15; }
        else if (xp > 388800) { return 14; }
        else if (xp > 259200) { return 13; }
        else if (xp > 172800) { return 12; }
        else if (xp > 115200) { return 11; }
        else if (xp > 76800) { return 10; }
        else if (xp > 51200) { return 9; }
        else if (xp > 25600) { return 8; }
        else if (xp > 12800) { return 7; }
        else if (xp > 6400) { return 6; }
        else if (xp > 3200) { return 5; }
        else if (xp > 1600) { return 4; }
        else if (xp > 800) { return 3; }
        else if (xp > 400) { return 2; }
        else { return 1; }
    }

    function accrue(Player calldata player, uint amount) public override {
        require(msg.sender == address(registry), "only callable from AdventureRegistry");

        accruedXP[player.toCompactForm()] += amount;
    }

    function balance(Player calldata player) public override view returns(uint) {
        return accruedXP[player.toCompactForm()];
    }

    function name() pure external override returns(string memory) {
        return "XP";
    }
}


contract BasicLootDungeon is Ownable, Adventure {
    uint constant TIME_TO_COMPLETE = 20 minutes;
    Experience xp;

    function init(address experienceContractAddress) external onlyOwner {
        xp = Experience(experienceContractAddress);
    }

    function name() pure external override returns(string memory) {
        return "Dungeon of noobing";
    }

    function canEnter(Player calldata) pure external override returns(bool, string memory) {
        return (true, "all are welcome");
    }

    function getTimeToComplete() pure public override returns(uint) {
        return TIME_TO_COMPLETE;
    }

    function getReward(Player calldata) view external override returns(PendingReward memory) {
        PendingReward memory reward;
        reward.unlockTimestamp = block.timestamp + getTimeToComplete();
        reward.rewardContract = address(xp);
        reward.minAmount = 100;
        reward.maxAmount = 200;
        return reward;
    }
}


contract Level2LootDungeon is Ownable, Adventure {
    uint constant TIME_TO_COMPLETE = 30 minutes;
    Experience xp;

    function init(address experienceContractAddress) external onlyOwner {
        xp = Experience(experienceContractAddress);
    }

    function name() pure external override returns(string memory) {
        return "Dungeon of unremarkable dangers";
    }

    function canEnter(Player calldata player) view external override returns(bool, string memory) {
        return (xp.levelOf(player) > 2, "player must be at least level 2 to enter this dungeon");
    }

    function getTimeToComplete() pure external override returns(uint) {
        return TIME_TO_COMPLETE;
    }

    function getReward(Player calldata) view external override returns(PendingReward memory) {
        PendingReward memory reward;
        reward.unlockTimestamp = block.timestamp + TIME_TO_COMPLETE;
        reward.rewardContract = address(xp);
        reward.minAmount = 150;
        reward.maxAmount = 400;
        return reward;
    }
}