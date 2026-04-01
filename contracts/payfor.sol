// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
}

contract PayGasForStaking {
    function executeSponsorStake(
        address usdc,
        address stakingAddress,
        uint256 amount,
        uint256 fee,
        address sponsor
    ) external {
        require(msg.sender == sponsor, "only sponsor");
        require(usdc != address(0), "invalid usdc");
        require(stakingAddress != address(0), "invalid staking");
        require(sponsor != address(0), "invalid sponsor");
        require(amount > fee, "fee exceeds amount");

        uint256 depositAmount = amount - fee;

        require(IERC20(usdc).transfer(sponsor, fee), "fee transfer failed");
        require(
            IERC20(usdc).approve(stakingAddress, depositAmount),
            "approve failed"
        );

        (bool success, bytes memory returndata) = stakingAddress.call(
            abi.encodeWithSignature("deposit(uint256)", depositAmount)
        );

        if (!success) {
            _revertWithReason(returndata, "deposit call failed");
        }
    }

    function executeSponsorWithdraw(
        address usdc,
        address stakingAddress,
        uint256 stakingId,
        uint256 fee,
        address sponsor
    ) external {
        require(msg.sender == sponsor, "only sponsor");
        require(usdc != address(0), "invalid usdc");
        require(stakingAddress != address(0), "invalid staking");
        require(sponsor != address(0), "invalid sponsor");
        require(stakingId > 0, "invalid stakingId");

        (bool success, bytes memory returndata) = stakingAddress.call(
            abi.encodeWithSignature("withdraw(uint256)", stakingId)
        );

        if (!success) {
            _revertWithReason(returndata, "withdraw call failed");
        }

        if (fee > 0) {
            require(IERC20(usdc).transfer(sponsor, fee), "fee transfer failed");
        }
    }

    function _revertWithReason(
        bytes memory returndata,
        string memory fallbackMessage
    ) private pure {
        if (returndata.length == 0) {
            revert(fallbackMessage);
        }

        assembly {
            revert(add(returndata, 0x20), mload(returndata))
        }
    }
}
