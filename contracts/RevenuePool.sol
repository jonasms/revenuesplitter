// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./interfaces/IRevenuePool.sol";
import "./RevenueSplitter.sol";

contract RevenuePool is RevenueSplitter {
    uint256 private constant MAX_TOKEN_SUPPLY = 100 ether;

    constructor(address owner, string memory uri_) RevenueSplitter(owner, uri_) {}

    function purchase() external payable {
        // require(totalSupply() + msg.value <= MAX_TOKEN_SUPPLY, "");
        _mint(msg.sender, 1, msg.value, "");
    }
}
