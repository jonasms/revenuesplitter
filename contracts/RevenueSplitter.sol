// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "./interfaces/IRevenueSplitter.sol";

contract RevenueSplitter is ERC20, IRevenueSplitter {
    address guardian;

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

        // mapping(address => Receipt) balanceOfLocked;
        // Receipt[] receipts;
    }

    RevenuePeriod[] private revenuePeriods;

    constructor(
        address guardian_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        guardian = guardian_;
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
    // function _beforeExecute(bytes calldata data_) internal virtual {
    //     console.log("PLACEHOLDER");
    // }

    // function _afterExecute(bytes calldata data_) internal virtual {
    //     console.log("PLACEHOLDER");
    // }

    function _onReceive() internal virtual {
        console.log("PLACEHOLDER");
    }

    // event PaymentReceived(address, uint256);
}
