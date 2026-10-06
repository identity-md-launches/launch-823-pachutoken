// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Pachu launch token
/// @notice Fixed supply, 18 decimals, and ordinary ERC-20 transfers without administrative powers.
/// @dev ProjectFactory receives the entire supply and performs the protocol's launch allocation.
contract LaunchToken is ERC20 {
    /// @notice Mint all 1,000,000,000 PACHU to the deployer, exactly once.
    constructor() ERC20("Pachu", "PACHU") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
