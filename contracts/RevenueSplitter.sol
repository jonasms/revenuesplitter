// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "./interfaces/IRevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenueSplitter is ERC1155 {
    uint256 public constant REVENUE_PERIOD_DURATION = 90 days;
    uint256 public constant TOKEN = 1;
    uint256 public constant TOKEN_OPTION = 2;

    /**
        Used to give users a period of time to vest unvested tokens
        before withdrawls from the revenue pool are made.
     */
    // uint256 private constant BLACKOUT_PERIOD = 7 days;

    address owner;

    // track funds collected in curPeriodFunds
    // set curPeriodFunds to lastPeriodFunds

    uint256 curLiquidityPer;

    // TODO using
    struct RevenuePeriod {
        // TODO data packing?
        uint256 date;
        uint256 revenue;
        uint256 totalSupplyUnvested; // TODO being used?
        mapping(address => uint256) balanceOfUnvested; // TODO being used?
    }

    struct TokenPurchase {
        // TODO data packing?
        uint256 vestingPeriod;
        uint256 balance;
        bool exercised;
    }

    mapping(address => TokenPurchase[]) private _tokenPurchases;
    mapping(address => uint256) private _balanceOfUnexercised; // TODO remove
    uint256 private _totalSupplyUnexercised; // TODO expose?

    uint256 private curRevenuePeriodId;
    uint256 public curRevenuePeriodDate;
    uint256 private curRevenuePeriodRevenue;
    uint256 private curRevenuePeriodTotalSupply;

    uint256 public lastRevenuePeriodDate;
    uint256 private lastRevenuePeriodRevenue;
    uint256 private lastRevenuePeriodTotalSupply;

    constructor(address owner_, string memory uri_) ERC1155(uri_) {
        owner = owner_;
        curRevenuePeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
    }

    // GETTERS
    // tokenPurchases ?

    /**
        TESTS
            1. Can redeem vested AND un-exercised shares once
            2. Returns the numbers of tokens minted
     */
    // Exercise vested tokens
    function redeem() public returns (uint256 exercisedTokensCount) {
        TokenPurchase[] storage tokenPurchases = _tokenPurchases[msg.sender];

        require(tokenPurchases.length > 0, "RevenueSplitter::redeem: ZERO_TOKEN_PURCHASES");

        for (uint256 i = 0; i < tokenPurchases.length; i++) {
            if (tokenPurchases[i].vestingPeriod <= curRevenuePeriodId && !tokenPurchases[i].exercised) {
                tokenPurchases[i].exercised = true;
                exercisedTokensCount += tokenPurchases[i].balance;
            }
        }

        require(exercisedTokensCount > 0, "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES");

        _burn(msg.sender, TOKEN_OPTION, exercisedTokensCount);
        _mint(msg.sender, TOKEN, exercisedTokensCount, "");

        // TODO emit Redeem event
    }

    function _addTokenPurchase(
        address addr_,
        uint256 vestingPeriod_,
        uint256 balance_
    ) internal {
        _tokenPurchases[addr_].push(TokenPurchase(vestingPeriod_, balance_, false));
    }

    function _mint(
        address to_,
        uint256 id_,
        uint256 amount_,
        bytes memory data_
    ) internal virtual override {
        if (id_ == TOKEN_OPTION) {
            _addTokenPurchase(to_, curRevenuePeriodId + 2, amount_);
        }

        super._mint(to_, id_, amount_, data_);
    }

    // function _beforeTokenTransfer(
    //     address,
    //     address,
    //     address to_,
    //     uint256[] memory ids_,
    //     uint256[] memory amounts_,
    //     bytes memory
    // ) internal virtual override {
    //     for (uint256 i = 0; i < ids_.length; i++) {
    //         if (ids_[i] == TOKEN_OPTION) {
    //             _addTokenPurchase(to_, block.timestamp, amounts_[i]);
    //         }
    //     }
    // }

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
            _mint(address(this), TOKEN, curRevenuePeriodTotalSupply, "");
        }

        _setLastRevenuePeriod(curRevenuePeriodDate, curRevenuePeriodRevenue, curRevenuePeriodTotalSupply);
        _setCurRevenuePeriod(block.timestamp + REVENUE_PERIOD_DURATION, 0, 0);
        curRevenuePeriodId++;

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

    /* ERC165 CONFIGs */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"));
    }

    // /* HOOKS */
    function _beforeTokenUnexercisedTransfer() internal virtual {}

    function _afterTokenUnexercisedTransfer() internal virtual {}

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
