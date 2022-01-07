// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "./interfaces/IRevenuePool.sol";
import "./RevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenuePool is RevenueSplitter {
    uint256 private constant MAX_TOKEN_SUPPLY = 100 ether; // TODO convert to state
    uint256 private constant TSX_FEE = 10;
    uint256 public exchangeRate; // TODO create setter
    bool public feesEnabled; // TODO create setter

    constructor(
        address owner_,
        uint256 maxTokenSupply_,
        uint256 exchangeRate_,
        string memory name_,
        string memory symbol_
    ) RevenueSplitter(owner_, maxTokenSupply_, name_, symbol_) {
        exchangeRate = exchangeRate_;
    }

    /* PRIMARY FEATURES */
    function depositLiquidity() external payable {
        (uint256 amountToMint, uint256 transactionFee) = getTokensLessFees(msg.value);

        amountToMint = amountToMint / exchangeRate;

        _deposit(msg.sender, amountToMint);

        if (transactionFee > 0) {
            _mint(owner, transactionFee);
        }
    }

    function withdrawRevenue() external {
        _withdrawRevenueShare(msg.sender);
    }

    /* OVERRIDES AND HOOKS */
    function _transfer(
        address to_,
        address from_,
        uint256 amount_
    ) internal virtual override {
        uint256 transactionFee;

        (amount_, transactionFee) = getTokensLessFees(amount_);

        if (transactionFee > 0) {
            super._transfer(from_, owner, transactionFee);
        }

        super._transfer(from_, to_, amount_);
    }

    /* HELPERS */
    function getTokensLessFees(uint256 amount_) internal view returns (uint256 amount, uint256 transactionFee) {
        if (feesEnabled) {
            transactionFee = (amount_ * TSX_FEE) / 1000;
            amount = amount_ - transactionFee;
        } else {
            amount = amount_;
        }
    }

    /* SETTERS */
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
