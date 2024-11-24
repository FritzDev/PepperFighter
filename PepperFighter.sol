// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PepperFighter is ERC721Enumerable, Ownable {
    IERC20 public pepperToken;
    uint256 public mintPrice = 100 * 10**18; // 100 PEPPER, assuming 18 decimals
    uint256 public maxSupply = 100;
    address public constant burnAddress = 0x000000000000000000000000000000000000dEaD;
    address public devAddress;

    struct Fight {
        address challenger;
        uint256 challengerTokenId;
        uint256 betAmount;
        bool active;
    }

    // Mapping for active fights
    mapping(uint256 => Fight) public fights;

    // Mapping for storing characteristics of each PepperFighter
    mapping(uint256 => uint256) public strength;
    mapping(uint256 => uint256) public agility;
    mapping(uint256 => uint256) public endurance;
    mapping(uint256 => uint256) public initiative;

    // Event for minting with characteristics
    event PepperFighterMinted(uint256 tokenId, uint256 strength, uint256 agility, uint256 endurance, uint256 initiative);
    event FightResult(uint256 winnerTokenId, uint256 loserTokenId, string report);
    event FightCreated(uint256 indexed tokenId, uint256 betAmount);
    event FightAccepted(uint256 indexed challengerTokenId, uint256 indexed opponentTokenId, uint256 potAmount);

    constructor(address _pepperTokenAddress, address _devAddress) ERC721("PepperFighter", "PF") {
        pepperToken = IERC20(_pepperTokenAddress);
        devAddress = _devAddress;
    }

    function mint(uint256 _amount) external {
        require(totalSupply() + _amount <= maxSupply, "Exceeds max supply");
        uint256 totalCost = mintPrice * _amount;
        uint256 burnAmount = totalCost / 2;
        uint256 devAmount = totalCost - burnAmount;

        require(
            pepperToken.transferFrom(msg.sender, burnAddress, burnAmount),
            "Token transfer to burn address failed"
        );
        require(
            pepperToken.transferFrom(msg.sender, devAddress, devAmount),
            "Token transfer to dev address failed"
        );

        for (uint256 i = 0; i < _amount; i++) {
            uint256 tokenId = totalSupply() + 1;

            // Generate random characteristics for each new PepperFighter
            uint256 randStrength = random(10, 20, tokenId); // Strength between 10 and 20
            uint256 randAgility = random(5, 15, tokenId); // Agility between 5 et 15
            uint256 randEndurance = random(50, 100, tokenId); // Endurance between 50 et 100
            uint256 randInitiative = random(1, 10, tokenId); // Initiative between 1 et 10

            // Store the characteristics
            strength[tokenId] = randStrength;
            agility[tokenId] = randAgility;
            endurance[tokenId] = randEndurance;
            initiative[tokenId] = randInitiative;

            // Mint the token
            _safeMint(msg.sender, tokenId);

            // Emit event
            emit PepperFighterMinted(tokenId, randStrength, randAgility, randEndurance, randInitiative);
        }
    }

    function createFight(uint256 tokenId, uint256 betAmount) external {
        require(ownerOf(tokenId) == msg.sender, "You must own the token to create a fight");
        require(betAmount > 0, "Bet amount must be greater than zero");
        require(
            pepperToken.transferFrom(msg.sender, address(this), betAmount),
            "Failed to transfer PEPPER tokens for bet"
        );

        fights[tokenId] = Fight({
            challenger: msg.sender,
            challengerTokenId: tokenId,
            betAmount: betAmount,
            active: true
        });

        emit FightCreated(tokenId, betAmount);
    }

    function acceptFight(uint256 challengerTokenId, uint256 opponentTokenId) external {
        Fight storage fight = fights[challengerTokenId];
        require(fight.active, "This fight is not active");
        require(ownerOf(opponentTokenId) == msg.sender, "You must own the opponent token to accept the fight");
        require(
            pepperToken.transferFrom(msg.sender, address(this), fight.betAmount),
            "Failed to transfer PEPPER tokens for bet"
        );

        fight.active = false;
        uint256 potAmount = fight.betAmount * 2;

        emit FightAccepted(fight.challengerTokenId, opponentTokenId, potAmount);

        // Conduct the fight
        _conductFight(fight.challengerTokenId, opponentTokenId, potAmount);
    }

    function _conductFight(uint256 tokenId1, uint256 tokenId2, uint256 potAmount) internal {
        // Copy initial endurance for the fight
        uint256 endurance1 = endurance[tokenId1];
        uint256 endurance2 = endurance[tokenId2];
        string memory report = "Fight Start:\n";

        // Combat loop
        while (endurance1 > 0 && endurance2 > 0) {
            uint256 roll1 = random(1, 100, tokenId1) + initiative[tokenId1];
            uint256 roll2 = random(1, 100, tokenId2) + initiative[tokenId2];

            while (roll1 == roll2) {
                roll1 = random(1, 100, tokenId1) + initiative[tokenId1];
                roll2 = random(1, 100, tokenId2) + initiative[tokenId2];
            }

            bool isToken1Turn = roll1 > roll2;

            if (isToken1Turn) {
                uint256 damage = calculateDamage(tokenId1);
                endurance2 = endurance2 > damage ? endurance2 - damage : 0;
                report = string(abi.encodePacked(report, "Token ", toString(tokenId1), " attacks Token ", toString(tokenId2), " for ", toString(damage), " damage. Endurance left: ", toString(endurance2), "\n"));
            } else {
                uint256 damage = calculateDamage(tokenId2);
                endurance1 = endurance1 > damage ? endurance1 - damage : 0;
                report = string(abi.encodePacked(report, "Token ", toString(tokenId2), " attacks Token ", toString(tokenId1), " for ", toString(damage), " damage. Endurance left: ", toString(endurance1), "\n"));
            }
        }

        // Determine winner and distribute the pot
        if (endurance1 > 0) {
            report = string(abi.encodePacked(report, "Token ", toString(tokenId1), " wins against Token ", toString(tokenId2), "\n"));
            pepperToken.transfer(ownerOf(tokenId1), potAmount);
            emit FightResult(tokenId1, tokenId2, report);
        } else {
            report = string(abi.encodePacked(report, "Token ", toString(tokenId2), " wins against Token ", toString(tokenId1), "\n"));
            pepperToken.transfer(ownerOf(tokenId2), potAmount);
            emit FightResult(tokenId2, tokenId1, report);
        }
    }

    // Function to generate pseudo-random numbers for characteristics
    function random(uint256 min, uint256 max, uint256 seed) internal view returns (uint256) {
        return min + uint256(keccak256(abi.encodePacked(block.timestamp, msg.sender, seed))) % (max - min + 1);
    }

    // Function to calculate damage, including potential critical hits
    function calculateDamage(uint256 tokenId) internal view returns (uint256) {
        uint256 baseDamage = strength[tokenId];
        uint256 roll = random(1, 100, tokenId);

        if (roll + agility[tokenId] >= 90) {
            uint256 criticalDamage = (baseDamage * 25 + 99) / 100;
            return baseDamage + criticalDamage;
        } else {
            return baseDamage;
        }
    }

    // Utility function to convert uint256 to string
    function toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}



