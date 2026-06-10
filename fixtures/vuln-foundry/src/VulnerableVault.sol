// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/// @title VulnerableVault
/// @notice Intentionally vulnerable fixture for isolated Olympix skill testing.
///         DO NOT deploy. Contains a deliberate reentrancy bug and a missing
///         access-control bug so BugPocer / static analysis produce deterministic findings.
contract VulnerableVault {
    mapping(address => uint256) public balances;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @dev BUG: state update happens AFTER the external call → classic reentrancy.
    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "insufficient");
        (bool ok, ) = msg.sender.call{value: amount}("");
        require(ok, "transfer failed");
        balances[msg.sender] -= amount;
    }

    /// @dev BUG: no access control — anyone can drain the contract.
    function sweep(address payable to) external {
        to.transfer(address(this).balance);
    }
}
