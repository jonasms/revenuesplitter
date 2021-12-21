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
        bool exercised;
    }

    mapping(address => UnvestedShare[]) private vestableShares;

    uint256 public curRevenuePeriodDate;
    uint256 private curRevenuePeriodRevenue;
    uint256 private curRevenuePeriodTotalSupply;

    uint256 private lastRevenuePeriodDate;
    uint256 private lastRevenuePeriodRevenue;
    uint256 private lastRevenuePeriodTotalSupply;

    constructor(
        address owner_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        owner = owner_;
        curRevenuePeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
    }

    function _getVestableSharesCount(address shareholder_, bool exercise)
        internal
        view
        returns (uint256 vestableSharesCount)
    {
        UnvestedShare[] memory _vestableShares = vestableShares[shareholder_];
        UnvestedShare memory curShare;
        for (uint256 i = 0; i < _vestableShares.length - 1; i++) {
            // TODO scrutinize gas optimization here
            curShare = _vestableShares[i];

            if (curShare.date >= curRevenuePeriodDate && !curShare.exercised) {
                vestableSharesCount += curShare.balance;

                if (exercise) {
                    _vestableShares[i].exercised = true;
                }
            }
        }
    }

    function getVestableSharesCount() public view returns (uint256) {
        return _getVestableSharesCount(msg.sender, false);
    }

    // function _mintUnvested
    /**
        TESTS
            1. Can redeem vested but un-exercised shares once
            2. Returns the numbers of tokens minted
     */
    function redeem() public returns (uint256 vestablSharesCount) {
        vestablSharesCount = _getVestableSharesCount(msg.sender, true);

        require(vestablSharesCount > 0, "RevenueSplitter::redeem: ZERO_VESTABLE_SHARES");

        _mint(msg.sender, vestablSharesCount);
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

    /**
        TESTING
            1. Fxn reverts if the current period is currently in progress
            2. Fxn sets `lastRevenuePeriod` and creates a new `curRevenuePeriod`
     */
    function endRevenuePeriod() public {
        // RevenuePeriod _curRevenuePeriod = curRevenuePeriod;
        require(
            block.timestamp >= curRevenuePeriodDate,
            "RevenueSplitter::endRevenuePeriod: REVENUE_PERIOD_IN_PROGRESS"
        );

        _beforeEndRevenuePeriod();

        // TODO what is this supposed to be doing?
        if (lastRevenuePeriodDate > 0) {
            _mint(address(this), curRevenuePeriodTotalSupply);
        }

        _setLastRevenuePeriod(curRevenuePeriodDate, curRevenuePeriodRevenue, curRevenuePeriodTotalSupply);
        _setCurRevenuePeriod(block.timestamp + REVENUE_PERIOD_DURATION, 0, 0);

        _afterEndRevenuePeriod();
    }

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
