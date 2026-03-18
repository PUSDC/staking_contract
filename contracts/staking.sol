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

struct Transfer {
    address fromAddr;
    address toAddr;
    uint256 amount;
    bool finished;
}

contract PayInboxV2 {
    string public chain_identifier;
    bool public live = true;
    uint256 public total = 0;
    uint256 public transfer_count = 0;

    address public erc20;
    address public witness;
    address public owner;
    address public operator;
    address public aave;

    mapping(address => uint256) public inboxBalances;
    mapping(uint256 => Transfer) public inboxTransfers;
    mapping(bytes32 => bool) public usedWithdrawAuthorizations;

    event InboxWithdraw(address indexed addr, uint256 amount);

    event InboxSend(uint256 indexed txNo);

    event InboxAccept(uint256 indexed txNo, uint256 convertAmount);

    event InboxRevoke(uint256 indexed txNo);
    event InboxWithdrawByOperator(
        address indexed operatorAddr,
        address indexed addr,
        uint256 amount
    );

    function called_when_upgrade() external {
        chain_identifier = "inbox_base_usdc";
        if (witness == address(0)) {
            witness = 0x78141a5a8C8Ba0595DC93c6dAb3A63270d6aA8B8;
        }
        if (owner == address(0)) {
            owner = 0xe1288759446298f250C3Bce5616706D25525Ba7F;
        }
        if (operator == address(0)) {
            operator = 0xe1288759446298f250C3Bce5616706D25525Ba7F;
        }
        if (aave == address(0)) {
            aave = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
        }
        if (erc20 == address(0)) {
            erc20 = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        }
    }

    function withdrawByUser(
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) external {
        require(amount > 0, "Amount must be > 0");
        require(block.timestamp <= deadline, "Signature expired");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                chain_identifier,
                "withdraw",
                msg.sender,
                amount,
                nonce,
                deadline,
                address(this),
                block.chainid
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        require(
            usedWithdrawAuthorizations[ethSignedMessageHash] == false,
            "Authorization already used"
        );

        address recoveredSigner = _recoverSigner(ethSignedMessageHash, signature);
        require(recoveredSigner == witness, "Invalid signature detected");
        usedWithdrawAuthorizations[ethSignedMessageHash] = true;

        _withdraw(msg.sender, amount);
        emit InboxWithdraw(msg.sender, amount);
    }

    // can be called by operator for gasless users
    function withdrawByOperator(address user, uint256 amount) external {
        require(msg.sender == operator, "Only operator");
        require(user != address(0), "Invalid user");
        require(amount > 0, "Amount must be > 0");
        _withdraw(user, amount);

        emit InboxWithdrawByOperator(msg.sender, user, amount);
    }

    // can be called by sender only
    function sendFund(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        // require(amount <= inboxBalances[msg.sender], "Insufficient balance");
        if (amount > inboxBalances[msg.sender]) {
            uint256 remain = amount - inboxBalances[msg.sender];
            inboxBalances[msg.sender] = 0;

            require(
                IERC20(erc20).transferFrom(msg.sender, address(this), remain),
                "Deposit failed"
            );

            IERC20(erc20).approve(aave, remain);
            IAave(aave).supply(erc20, remain, address(this), 0);

            total += remain;
        } else {
            inboxBalances[msg.sender] -= amount;
        }

        transfer_count += 1;
        uint256 txNo = transfer_count;
        inboxTransfers[txNo] = Transfer({
            fromAddr: msg.sender,
            toAddr: address(0),
            amount: amount,
            finished: false
        });

        emit InboxSend(txNo);
    }

    // can be called by receiver only, with witness signature
    function acceptFundByUser(
        uint256 txNo,
        address toAddr,
        uint256 convertAmount,
        bytes memory signature
    ) external {
        require(toAddr != address(0), "Invalid recipient address");
        require(msg.sender == toAddr, "Invalid sender address");

        bytes32 messageHash = keccak256(
            abi.encodePacked(
                chain_identifier,
                msg.sender,
                txNo,
                toAddr,
                convertAmount
            )
        );
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );

        address recoveredSigner = _recoverSigner(ethSignedMessageHash, signature);
        require(recoveredSigner == witness, "Invalid signature detected");

        _acceptFund(txNo, toAddr, convertAmount);
    }

    // can be called by operator only, no witness signature needed
    function acceptFundByOperator(
        uint256 txNo,
        address toAddr,
        uint256 convertAmount
    ) external {
        require(msg.sender == operator, "Only operator");
        require(toAddr != address(0), "Invalid recipient address");
        _acceptFund(txNo, toAddr, convertAmount);
    }

    // can be called by the sender only
    function revokeFund(uint256 txNo) external {
        require(inboxTransfers[txNo].fromAddr != address(0), "Invalid txNo");
        require(inboxTransfers[txNo].fromAddr == msg.sender, "Invalid sender");
        require(inboxTransfers[txNo].finished == false, "Invalid transfer");

        inboxBalances[msg.sender] += inboxTransfers[txNo].amount;
        // inboxTransfers[txNo].amount = 0;
        inboxTransfers[txNo].finished = true;

        emit InboxRevoke(txNo);
    }

    function _withdraw(address user, uint256 amount) internal {
        require(inboxBalances[user] >= amount, "Insufficient balance");
        inboxBalances[user] -= amount;
        total -= amount;

        IAave(aave).withdraw(erc20, amount, address(this));
        require(IERC20(erc20).transfer(user, amount), "Withdraw failed");
    }

    function _acceptFund(
        uint256 txNo,
        address toAddr,
        uint256 convertAmount
    ) internal {
        Transfer memory transfer = inboxTransfers[txNo];
        require(transfer.fromAddr != address(0), "Invalid txNo");
        require(transfer.finished == false, "Transfer already finished");

        inboxBalances[toAddr] += transfer.amount;
        inboxTransfers[txNo].finished = true;
        inboxTransfers[txNo].toAddr = toAddr;

        emit InboxAccept(txNo, convertAmount);
    }

    // ============ Utility Functions ============
    function _recoverSigner(
        bytes32 ethSignedMessageHash,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Adjust v if necessary
        if (v < 27) {
            v += 27;
        }

        require(v == 27 || v == 28, "Invalid signature v value");

        return ecrecover(ethSignedMessageHash, v, r, s);
    }
}
