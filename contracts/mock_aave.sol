// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MockAave {
    mapping(address => uint256) public deposits;

    event Supply(address indexed user, address indexed asset, uint256 amount);
    event Withdraw(address indexed user, address indexed asset, uint256 amount);

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external {
        IERC20 assetToken = IERC20(asset);
        require(
            assetToken.transferFrom(msg.sender, address(this), amount),
            "Supply transfer failed"
        );
        deposits[asset] += amount;
        emit Supply(onBehalfOf, asset, amount);
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        require(deposits[asset] >= amount, "Insufficient deposit");
        deposits[asset] -= amount;
        IERC20 assetToken = IERC20(asset);
        require(assetToken.transfer(to, amount), "Withdraw transfer failed");
        emit Withdraw(to, asset, amount);
        return amount;
    }
}
