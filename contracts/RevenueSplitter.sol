// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IRevenueSplitter.sol";

contract RevenueSplitter is ERC20 {
    uint256 private constant REVENUE_PERIOD_DURATION = 90 days;

    /**
        Used to give users a period of time to vest unvested tokens
        before withdrawls from the revenue pool are made.
     */
    // uint256 private constant BLACKOUT_PERIOD = 7 days;

    address owner;

    // track funds collected in curPeriodFunds
    // set curPeriodFunds to lastPeriodFunds

    uint256 curLiquidityPer;

    struct Receipt {
        address from;
        uint256 date;
        uint256 amount;
    }

    struct RevenuePeriod {
        // TODO data packing?
        uint256 date;
        uint256 revenue;
        uint256 totalSupplyUnvested;
        mapping(address => uint256) balanceOfUnvested;
    }

    struct UnvestedShare {
        uint256 date;
        uint256 balance;
    }

    mapping(address => UnvestedShare[]) unvestedShares;

    uint256 curRevenuePeriodDate;
    uint256 curRevenuePeriodRevenue;
    uint256 curRevenuePeriodTotalSupply;

    uint256 lastRevenuePeriodDate;
    uint256 lastRevenuePeriodRevenue;
    uint256 lastRevenuePeriodTotalSupply;

    // RevenuePeriod curRevenuePeriod;
    // RevenuePeriod lastRevenuePeriod;

    constructor(
        address owner_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        owner = owner_;
        curRevenuePeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
    }

    function _getVestableShares(address shareholder_) internal view returns (UnvestedShare[] memory vestableShares) {
        UnvestedShare[] memory _unvestedShares = unvestedShares[shareholder_];
        UnvestedShare memory curShare;
        for (uint256 i = 0; i < _unvestedShares.length - 1; i++) {
            // TODO scrutinize gas optimization here
            curShare = _unvestedShares[i];

            if (curShare.date >= curRevenuePeriodDate) {
                vestableShares[i] = curShare;
            }
        }
    }

    function _setCurRevenuePeriod(
        uint256 date_,
        uint256 revenue_,
        uint256 totalSupply_
    ) internal {
        curRevenuePeriodDate = date_;
        curRevenuePeriodRevenue = revenue_;
        curRevenuePeriodTotalSupply = totalSupply_;
    }

    function _setLastRevenuePeriod(
        uint256 date_,
        uint256 revenue_,
        uint256 totalSupply_
    ) internal {
        lastRevenuePeriodDate = date_;
        lastRevenuePeriodRevenue = revenue_;
        lastRevenuePeriodTotalSupply = totalSupply_;
    }

    function getVestableShares() public view returns (UnvestedShare[] memory) {
        return _getVestableShares(msg.sender);
    }

    function endRevenuePeriod() public {
        // RevenuePeriod _curRevenuePeriod = curRevenuePeriod;
        require(
            block.timestamp >= curRevenuePeriodDate,
            "RevenueSplitter::endRevenuePeriod: REVENUE_PERIOD_IN_PROGRESS"
        );

        _beforeEndRevenuePeriod();

        if (lastRevenuePeriodDate > 0) {
            _mint(address(this), curRevenuePeriodTotalSupply);
        }

        // set lastRevenuePeriod to curRevenuePeriod
        _setLastRevenuePeriod(curRevenuePeriodDate, curRevenuePeriodRevenue, curRevenuePeriodTotalSupply);

        // create new revenue period
        _setCurRevenuePeriod(block.timestamp + REVENUE_PERIOD_DURATION, 0, 0);

        _afterEndRevenuePeriod();
    }

    function _endRevenuePeriod() internal virtual {}

    // function _deposit(address to_) internal virtual {
    //     // calculate tokens to transfer given ETH received
    //     // _mint tokens to sender
    // }

    // function deposit() external payable virtual {
    //     _deposit(msg.sender);
    // }

    // function queue()

    // function _execute(bytes calldata data_) internal virtual {
    //     require(msg.sender == guardian, "RevenueSharing::execute: GUARDIAN_ONLY");
    //     // don't allow calling own contract
    //     // execute call
    //     // return call result
    // }

    // function execute(bytes calldata data_) external override {
    //     _beforeExecute(data_);

    //     // TODO throw on call failure?
    //     _execute(data_);

    //     _afterExecute(data_);
    // }

    // // function withdraw()
    // // function withdraw(address receiver_)
    // // function _withdraw(address account_) internal virtual
    // // _beforeWithdraw(address receiver_, uint amount_) + _afterWithdraw(address receiver_, uint amount_)

    receive() external payable {
        _onReceive();
        emit PaymentReceived(msg.sender, msg.value);
    }

    // // setGuardian()

    // /* HOOKS */
    function _beforeEndRevenuePeriod() internal virtual {}

    function _afterEndRevenuePeriod() internal virtual {}

    // function _beforeExecute(bytes calldata data_) internal virtual {
    //     console.log("PLACEHOLDER");
    // }

    // function _afterExecute(bytes calldata data_) internal virtual {
    //     console.log("PLACEHOLDER");
    // }

    function _onReceive() internal virtual {
        console.log("PLACEHOLDER");
    }

    event PaymentReceived(address, uint256);
}
