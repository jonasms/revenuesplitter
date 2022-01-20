// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IRevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenueSplitter is ERC20 {
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    // TODO change to 30 days?
    uint256 public constant REVENUE_PERIOD_DURATION = 90 days;

    /**
        Used to give users a period of time to vest unvested tokens
        before withdrawls from the revenue pool are made.
     */
    // uint256 private constant BLACKOUT_PERIOD = 7 days;

    address public owner;
    uint256 public maxTokenSupply;

    struct RevenuePeriod {
        // TODO data packing?
        uint256 date;
        uint256 revenue;
        uint256 totalSupplyUnvested; // TODO being used?
        mapping(address => uint256) balanceOfUnvested; // TODO being used?
    }

    struct RestrictedTokenGrant {
        // TODO data packing?
        uint256 vestingPeriod; // TODO change to `vestingDate`?
        uint256 amount;
        bool exercised;
    }

    mapping(address => RestrictedTokenGrant[]) private _tokenGrants;
    uint256 private _totalSupplyUnexercised;

    uint256 public curRevenuePeriodId;

    // TODO convert to arrays?
    // TODO check accessibility
    uint256 public curRevenuePeriodDate;
    uint256 private curRevenuePeriodRevenue;
    uint256 private curRevenuePeriodTotalSupply; // TODO being used?

    uint256 public lastRevenuePeriodDate;
    uint256 internal lastRevenuePeriodRevenue;
    uint256 private lastRevenuePeriodTotalSupply; // TODO being used?

    // @dev map revenuePeriodId's to user addresses to the amount of ETH they've withdrawn in the given period
    mapping(uint256 => mapping(address => uint256)) private withdrawlReceipts;

    constructor(
        address owner_,
        uint256 maxTokenSupply_,
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {
        owner = owner_;
        maxTokenSupply = maxTokenSupply_;
        // TODO set first revenue period end date in separate fxn?
        curRevenuePeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
    }

    // GETTERS
    // tokenPurchases ?
    // TODO test if can override this to make it 'internal'. Otherwise, I'm unsure of the purpose of this.
    function totalSupplyUnexercised() public view virtual returns (uint256) {
        return _totalSupplyUnexercised;
    }

    function balanceOfUnexercised(address account_) public view virtual returns (uint256 balanceUnexercised) {
        RestrictedTokenGrant[] storage tokenGrants = _tokenGrants[account_];
        for (uint256 i = 0; i < tokenGrants.length; i++) {
            if (!tokenGrants[i].exercised) {
                balanceUnexercised += tokenGrants[i].amount;
            }
        }
    }

    // _deposit(address account_, uint amount_) internal virtual
    //  - require deposit amount less than max supply
    //  - calculates amount to mint
    //  - handles transaction fee
    //
    //  - mints or a grant token
    //  - emits event
    function _deposit(address account_, uint256 amount_) internal virtual {
        require(
            totalSupply() + _totalSupplyUnexercised + amount_ <= maxTokenSupply,
            "RevenueSplitter::_deposit: MAX_TOKEN_LIMIT"
        );

        // mint tokens if in first revenue period
        // otherwise, grant restricted tokens
        // TODO make conditional more dynamic?
        if (lastRevenuePeriodDate == 0) {
            _mint(account_, amount_);
        } else {
            _createTokenGrant(account_, curRevenuePeriodId + 2, amount_);
        }
    }

    function deposit() external payable virtual {
        _deposit(msg.sender, msg.value);
    }

    function _withdraw(address account_) internal virtual {
        require(lastRevenuePeriodRevenue > 0, "RevenueSplitter::_withdraw: ZERO_REVENUE");

        uint256 withdrawlPower = _getCurWithdrawlPower(account_);

        require(withdrawlPower > 0, "RevenueSplitter::_withdraw: ZERO_WITHDRAWL_POWER");

        // TODO will this work w/ miniscule shares?
        uint256 share = (withdrawlPower * 1000) / totalSupply();
        uint256 ethShare = share * (lastRevenuePeriodRevenue / 1000);

        withdrawlReceipts[curRevenuePeriodId - 1][account_] += withdrawlPower;
        (bool success, ) = account_.call{ value: ethShare }("");
        require(success, "RevenueSplitter::_withdrawRevenueShare: REQUEST_FAILED");
        // TODO handle bytes error message
        // TODO emit event
    }

    function withdraw() external virtual {
        _withdraw(msg.sender);
    }

    function withdrawBulk(
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external {
        require(vList_.length == rList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_R_LIST");
        require(vList_.length == sList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_S_LIST");
        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator));
        address signer;

        for (uint256 i = 0; i < vList_.length; i++) {
            /* Get Signer */
            signer = ecrecover(digest, vList_[i], rList_[i], sList_[i]);
            _withdraw(signer);
        }
    }

    // TODO return `exercisedTokensCount`?
    // TODO make internal, takes an `address to_` param
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
        _totalSupplyUnexercised -= exercisedTokensCount;
        _mint(msg.sender, exercisedTokensCount);

        emit Redeem(msg.sender, curRevenuePeriodId, exercisedTokensCount);
    }

    // TODO redeemBatched()

    // TODO rename
    function _createTokenGrant(
        address addr_,
        uint256 vestingPeriod_,
        uint256 amount_
    ) internal {
        _totalSupplyUnexercised += amount_;
        _tokenGrants[addr_].push(RestrictedTokenGrant(vestingPeriod_, amount_, false));

        // TODO emit event
    }

    function _getCurWithdrawlPower(address account_) internal view returns (uint256 amount) {
        amount = balanceOf(account_) - withdrawlReceipts[curRevenuePeriodId - 1][account_];
    }

    function getCurWithdrawlPower() external view returns (uint256) {
        return _getCurWithdrawlPower(msg.sender);
    }

    // prevent tokens being used for a withdrawl more than once per revenue period
    // allows transfer of tokens that have been used to withdraw funds in the current period
    function _transfer(
        address to_,
        address from_,
        uint256 amount_
    ) internal virtual override {
        uint256 fromWithdrawlPower = _getCurWithdrawlPower(from_);

        uint256 withdrawlReceiptTransfer = amount_ >= fromWithdrawlPower ? amount_ - fromWithdrawlPower : amount_;

        // TODO test scenario
        //  user withdrawls
        //  user redeems tokens
        //  user transfers more than amt tokens just reedemed (transferring tokens withdrawn in the current period)
        //  to_ user should only be able to withdraw up to the amt of tokens just reedemed

        withdrawlReceipts[curRevenuePeriodId - 1][to_] += withdrawlReceiptTransfer;
        // TODO reduce from_'s withdrawn amount

        super._transfer(from_, to_, amount_);
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
        // TODO use `curRevenuePeriodDate` value?

        // TODO set curPeriod revenue to remaining lastPeriod revenue
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
        curRevenuePeriodRevenue += msg.value;
        emit PaymentReceived(msg.sender, msg.value);
    }

    // setGuardian()

    /* SETTERS */
    function setMaxTokenSupply(uint256 maxTokenSupply_) external {
        require(msg.sender == owner, "RevenuePool::setMaxTokenSupply: ONLY_OWNER");
        maxTokenSupply = maxTokenSupply_;
    }

    /* UTILS */
    function getChainId() internal view returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    /* HOOKS */
    // TODO add params to fxns
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
