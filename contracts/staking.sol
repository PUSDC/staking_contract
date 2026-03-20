// SPDX-License-Identifier: MIT

pragma solidity ^0.8.31;

interface IERC20 {
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}

interface IAave {
    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

// Renamed from Transfer to Staking
struct Staking {
    address user;
    uint256 amount;
    uint256 timestamp;
    bool withdrawn;
}

contract BBSStaking {
    address public erc20;
    address public aave;
    address public owner;
    
    uint256 public minDeposit = 0;
    uint256 public totalStaked = 0;
    uint256 public stakingCount = 0;

    mapping(address => uint256) public stakedBalances;
    mapping(uint256 => Staking) public stakings;

    event Deposited(address indexed user, uint256 amount, uint256 stakingId);
    event Withdrawn(address indexed user, uint256 amount);
    event MinDepositUpdated(uint256 newMinDeposit);


    constructor(address _erc20, address _aave) {
        erc20 = _erc20;
        aave = _aave;
        owner = msg.sender;
    }

    function setMinDeposit(uint256 _amount) external {
        require(msg.sender == owner, "Only owner");
        minDeposit = _amount;
        emit MinDepositUpdated(_amount);
    }

    function deposit(uint256 amount) external {
        require(amount >= minDeposit, "Amount below minimum deposit");
        require(amount > 0, "Amount must be > 0");

        require(
            IERC20(erc20).transferFrom(msg.sender, address(this), amount),
            "Transfer from user failed"
        );

        // Supply to Aave to earn interest
        IERC20(erc20).approve(aave, amount);
        IAave(aave).supply(erc20, amount, address(this), 0);

        stakedBalances[msg.sender] += amount;
        totalStaked += amount;

        stakingCount++;
        stakings[stakingCount] = Staking({
            user: msg.sender,
            amount: amount,
            timestamp: block.timestamp,
            withdrawn: false
        });

        emit Deposited(msg.sender, amount, stakingCount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(stakedBalances[msg.sender] >= amount, "Insufficient staked balance");

        stakedBalances[msg.sender] -= amount;
        totalStaked -= amount;

        // Withdraw from Aave
        IAave(aave).withdraw(erc20, amount, address(this));
        
        require(
            IERC20(erc20).transfer(msg.sender, amount),
            "Transfer to user failed"
        );

        emit Withdrawn(msg.sender, amount);
    }

    function setOwner(address _newOwner) external {
        require(msg.sender == owner, "Only owner");
        owner = _newOwner;
    }
}
