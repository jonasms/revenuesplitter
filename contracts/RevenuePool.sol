// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./interfaces/IRevenuePool.sol";
import "./RevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenuePool is RevenueSplitter {
    uint256 private constant MAX_TOKEN_SUPPLY = 100 ether;

    constructor(address owner, string memory uri_) RevenueSplitter(owner, uri_) {}

    function deposit() external payable {
        // require(totalSupply() + msg.value <= MAX_TOKEN_SUPPLY, "");
        uint256 tokenId = lastRevenuePeriodDate == 0 ? TOKEN : TOKEN_OPTION;

        _mint(msg.sender, tokenId, msg.value, "");
    }
}
