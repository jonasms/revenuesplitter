// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./interfaces/IRevenuePool.sol";
import "./RevenueSplitter.sol";

contract RevenuePool is RevenueSplitter {
    uint256 private constant MAX_TOKEN_SUPPLY = 100 ether;

    constructor(
        address guardian_,
        string memory name_,
        string memory symbol_
    ) RevenueSplitter(guardian_, name_, symbol_) {
        guardian = guardian_;
    }

    function purchase() external payable {
        require(totalSupply() + msg.value <= MAX_TOKEN_SUPPLY, "");
        _mint(msg.sender, msg.value);
    }
}
