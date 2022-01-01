// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./interfaces/IRevenuePool.sol";
import "./RevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenuePool is RevenueSplitter {
    uint256 private constant MAX_TOKEN_SUPPLY = 100 ether; // TODO convert to state
    uint256 private constant TSX_FEE = 10;
    address private treasuryAddress;
    uint256 public maxTokenSupply;
    uint256 public exchangeRate; // TODO create setter
    bool public feesEnabled; // TODO create setter

    constructor(
        address owner_,
        address treasuryAddress_,
        uint256 maxTokenSupply_,
        uint256 exchangeRate_,
        string memory name_,
        string memory symbol_
    ) RevenueSplitter(owner_, name_, symbol_) {
        treasuryAddress = treasuryAddress_;
        maxTokenSupply = maxTokenSupply_;
        exchangeRate = exchangeRate_;
    }

    /* PRIMARY FEATURES */
    function deposit() external payable {
        require(
            totalSupply() + totalSupplyUnexercised() + msg.value <= maxTokenSupply,
            "RevenuePool::deposit: MAX_TOKEN_LIMIT"
        );

        uint256 amountToMint;
        uint256 transactionFee;

        if (feesEnabled) {
            transactionFee = (msg.value * TSX_FEE) / 1000;
            amountToMint = msg.value - transactionFee;
        } else {
            amountToMint = msg.value;
        }

        amountToMint = amountToMint / exchangeRate;

        // mint tokens if in first revenue period
        // otherwise, grant restricted tokens
        if (lastRevenuePeriodDate == 0) {
            _mint(msg.sender, amountToMint);
        } else {
            _createTokenGrant(msg.sender, curRevenuePeriodId + 2, amountToMint);
        }

        if (transactionFee > 0) {
            _mint(treasuryAddress, transactionFee);
        }
    }

    /* SETTERS */
    function setMaxTokenSupply(uint256 maxTokenSupply_) external {
        require(msg.sender == owner, "RevenuePool::setMaxTokenSupply: ONLY_OWNER");
        maxTokenSupply = maxTokenSupply_;
    }

    function setExchangeRate(uint256 exchangeRate_) external {
        require(msg.sender == owner, "RevenuePool::setExchangeRate: ONLY_OWNER");
        exchangeRate = exchangeRate_;
    }

    function toggleFees() external {
        require(msg.sender == owner, "RevenuePool::toggleFees: ONLY_OWNER");
        feesEnabled = !feesEnabled;
    }

    // _onReceive()
    //  - IF in first 2/3rds of period, invest capital

    // _beforeEndRevenuePeriod()
    //  - liquidate investments

    // liquidate()
}
