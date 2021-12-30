// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IRevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenueSplitter is ERC20 {
    uint256 public constant REVENUE_PERIOD_DURATION = 90 days;

    /**
        Used to give users a period of time to vest unvested tokens
        before withdrawls from the revenue pool are made.
     */
    // uint256 private constant BLACKOUT_PERIOD = 7 days;

    address public owner;

    struct RevenuePeriod {
        // TODO data packing?
        uint256 date;
        uint256 revenue;
        uint256 totalSupplyUnvested; // TODO being used?
        mapping(address => uint256) balanceOfUnvested; // TODO being used?
    }

    struct RestrictedTokenGrant {
        // TODO data packing?
        uint256 vestingPeriod;
        uint256 amount;
        bool exercised;
    }

    mapping(address => RestrictedTokenGrant[]) private _tokenGrants;
    uint256 private _totalSupplyUnexercised;

    uint256 public curRevenuePeriodId;
    uint256 public curRevenuePeriodDate;
    uint256 private curRevenuePeriodRevenue;
    uint256 private curRevenuePeriodTotalSupply; // TODO being used?

    uint256 public lastRevenuePeriodDate;
    uint256 private lastRevenuePeriodRevenue;
    uint256 private lastRevenuePeriodTotalSupply; // TODO being used?

    constructor(
        address owner_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        owner = owner_;
        // TODO set first revenue period end date in separate fxn?
        curRevenuePeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
    }

    // GETTERS
    // tokenPurchases ?
    // TODO test if can override this to make it 'internal'. Otherwise, I'm unsure of the purpose of this.
    function totalSupplyUnexercised() public view virtual returns (uint256) {
        return _totalSupplyUnexercised;
    }

    function balanceOfUnexercised(address account_) public view virtual returns (uint256) {
        console.log("BALANCE OF UNEXERCISED");
        uint256 amountUnexercised = 0;
        RestrictedTokenGrant[] storage tokenGrants = _tokenGrants[account_];
        console.log("NUM TOKEN GRANTS: ", tokenGrants.length);
        for (uint256 i = 0; i < tokenGrants.length; i++) {
            if (!tokenGrants[i].exercised) {
                amountUnexercised += tokenGrants[i].amount;
            }
        }
        console.log("AMOUNT UNEXERCISED: ", amountUnexercised);
        return amountUnexercised;
    }

    // TODO return `exercisedTokensCount`?
    // Exercise vested tokens
    function redeem() public returns (uint256 exercisedTokensCount) {
        RestrictedTokenGrant[] storage tokenGrants = _tokenGrants[msg.sender];

        require(tokenGrants.length > 0, "RevenueSplitter::redeem: ZERO_TOKEN_PURCHASES");

        for (uint256 i = 0; i < tokenGrants.length; i++) {
            if (tokenGrants[i].vestingPeriod <= curRevenuePeriodId && !tokenGrants[i].exercised) {
                tokenGrants[i].exercised = true;
                exercisedTokensCount += tokenGrants[i].amount;
            }
        }

        require(exercisedTokensCount > 0, "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES");

        // TODO decrease _totalSupplyRestricted by exercisedTokensCount

        // TODO remove _burn
        // TODO modify _mint, ERC20
        // _burn(msg.sender, TOKEN_OPTION, exercisedTokensCount); // removing this makes for a ~16.6% reduction in gas fees
        _mint(msg.sender, exercisedTokensCount);

        emit Redeem(msg.sender, curRevenuePeriodId, exercisedTokensCount);
    }

    // TODO rename
    function _createTokenGrant(
        address addr_,
        uint256 vestingPeriod_,
        uint256 amount_
    ) internal {
        _tokenGrants[addr_].push(RestrictedTokenGrant(vestingPeriod_, amount_, false));
    }

    // TODO remove?
    // function _mint(
    //     address to_,
    //     uint256 id_,
    //     uint256 amount_,
    //     bytes memory data_
    // ) internal virtual override {
    //     // TODO do this elsewhere
    //     if (id_ == TOKEN_OPTION) {
    //         _createTokenGrant(to_, curRevenuePeriodId + 2, amount_);
    //     }

    //     _totalSupply[id_] += amount_;

    //     super._mint(to_, id_, amount_, data_);
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
        require(
            block.timestamp >= curRevenuePeriodDate,
            "RevenueSplitter::endRevenuePeriod: REVENUE_PERIOD_IN_PROGRESS"
        );

        _beforeEndRevenuePeriod();

        _setLastRevenuePeriod(curRevenuePeriodDate, curRevenuePeriodRevenue, curRevenuePeriodTotalSupply);
        _setCurRevenuePeriod(block.timestamp + REVENUE_PERIOD_DURATION, 0, 0);
        curRevenuePeriodId++;

        _afterEndRevenuePeriod();

        emit EndPeriod(curRevenuePeriodId, curRevenuePeriodRevenue, curRevenuePeriodTotalSupply);
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

    // setGuardian()

    /* HOOKS */
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

    function _onReceive() internal virtual {}

    event PaymentReceived(address, uint256);

    event Redeem(address, uint256, uint256);

    event EndPeriod(uint256, uint256, uint256);
}
