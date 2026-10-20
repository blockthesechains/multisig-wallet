// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiSigWallet {
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    address[] public owners;
    mapping(address => bool) public isOwner;
    uint256 public immutable threshold;

    Transaction[] public transactions;
    mapping(uint256 => mapping(address => bool)) public isConfirmed;

    event Deposit(address indexed sender, uint256 amount);
    event TransactionSubmitted(uint256 indexed txId, address indexed owner, address indexed to, uint256 value, bytes data);
    event TransactionConfirmed(uint256 indexed txId, address indexed owner);
    event ConfirmationRevoked(uint256 indexed txId, address indexed owner);
    event TransactionExecuted(uint256 indexed txId, address indexed owner);

    error NotOwner();
    error InvalidOwner();
    error DuplicateOwner();
    error InvalidThreshold();
    error TxDoesNotExist();
    error TxAlreadyExecuted();
    error TxAlreadyConfirmed();
    error TxNotConfirmed();
    error NotEnoughConfirmations();
    error TxFailed();

    modifier onlyOwner() {
        if (!isOwner[msg.sender]) revert NotOwner();
        _;
    }

    modifier txExists(uint256 txId) {
        if (txId >= transactions.length) revert TxDoesNotExist();
        _;
    }

    modifier notExecuted(uint256 txId) {
        if (transactions[txId].executed) revert TxAlreadyExecuted();
        _;
    }

    constructor(address[] memory owners_, uint256 threshold_) {
        if (owners_.length == 0 || threshold_ == 0 || threshold_ > owners_.length) {
            revert InvalidThreshold();
        }

        for (uint256 i = 0; i < owners_.length; i++) {
            address owner = owners_[i];
            if (owner == address(0)) revert InvalidOwner();
            if (isOwner[owner]) revert DuplicateOwner();

            isOwner[owner] = true;
            owners.push(owner);
        }

        threshold = threshold_;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }

    function submitTransaction(address to, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (uint256 txId)
    {
        txId = transactions.length;
        transactions.push(
            Transaction({to: to, value: value, data: data, executed: false, confirmations: 0})
        );
        emit TransactionSubmitted(txId, msg.sender, to, value, data);
    }

    function confirmTransaction(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        if (isConfirmed[txId][msg.sender]) revert TxAlreadyConfirmed();

        isConfirmed[txId][msg.sender] = true;
        transactions[txId].confirmations += 1;
        emit TransactionConfirmed(txId, msg.sender);
    }

    function revokeConfirmation(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        if (!isConfirmed[txId][msg.sender]) revert TxNotConfirmed();

        isConfirmed[txId][msg.sender] = false;
        transactions[txId].confirmations -= 1;
        emit ConfirmationRevoked(txId, msg.sender);
    }

    function executeTransaction(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        Transaction storage txn = transactions[txId];
        if (txn.confirmations < threshold) revert NotEnoughConfirmations();

        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        if (!success) revert TxFailed();

        emit TransactionExecuted(txId, msg.sender);
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function transactionCount() external view returns (uint256) {
        return transactions.length;
    }
}