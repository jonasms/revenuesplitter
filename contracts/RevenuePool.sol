// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./interfaces/IRevenuePool.sol";
import "./RevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenuePool is RevenueSplitter {
    uint256 private constant MAX_TOKEN_SUPPLY = 100 ether;

    constructor(
        address owner_,
        string memory name_,
        string memory symbol_
    ) RevenueSplitter(owner_, name_, symbol_) {}

    function deposit() external payable {
        require(
            totalSupply() + totalSupplyUnexercised() + msg.value <= MAX_TOKEN_SUPPLY,
            "RevenuePool::deposit: MAX_TOKEN_LIMIT"
        );

        // mint tokens if in first revenue period
        // otherwise, grant restricted tokens
        if (lastRevenuePeriodDate == 0) {
            _mint(msg.sender, msg.value);
        } else {
            _createTokenGrant(msg.sender, curRevenuePeriodId + 2, msg.value);
        }
    }
}
