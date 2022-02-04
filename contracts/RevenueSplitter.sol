// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IRevenueSplitter.sol";

// TODO remove
import "hardhat/console.sol";

contract RevenueSplitter is ERC20 {
    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the revenue period timestamp used by the contract
    bytes32 private constant REVENUE_PERIOD_DATE_TYPEHASH = keccak256("LastPeriod(uint256 date)");

    // TODO change to 30 days?
    uint256 public constant REVENUE_PERIOD_DURATION = 30 days;
    uint256 public constant BLACKOUT_PERIOD_DURATION = 3 days;

    /**
        Used to give users a period of time to vest unvested tokens
        before withdrawls from the revenue pool are made.
     */
    // uint256 private constant BLACKOUT_PERIOD = 7 days;

    address public owner;
    uint256 public maxTokenSupply; // TODO make into constant

    struct Period {
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

    uint256 public curPeriodId;

    // TODO convert to arrays?
    // TODO check accessibility
    uint256 public curPeriodDate;
    uint256 private curPeriodRevenue;
    uint256 private curPeriodTotalSupply; // TODO being used?

    uint256 public lastPeriodDate;
    uint256 internal lastPeriodRevenue;
    uint256 private lastPeriodTotalSupply; // TODO being used?

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
        uint256 initialPeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
        curPeriodDate = initialPeriodDate;

        emit StartPeriod(0, initialPeriodDate, 0, 0);
    }

    // GETTERS
    // TODO delete
    function getLastPeriod() external view returns (uint256 revenuePeriodDate, uint256 revenuePeriodRevenue) {
        revenuePeriodDate = lastPeriodDate;
        revenuePeriodRevenue = lastPeriodRevenue;
    }

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

    function _isBlackoutPeriod() internal view returns (bool) {
        uint256 curPeriodStartTime = curPeriodDate - REVENUE_PERIOD_DURATION;
        return BLACKOUT_PERIOD_DURATION >= block.timestamp - curPeriodStartTime;
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
        if (lastPeriodDate == 0) {
            _mint(account_, amount_);
        } else {
            _createTokenGrant(account_, curPeriodId + 2, amount_);
        }

        // TODO should deposits be added to curPeriodRevenue?
        // TODO emit event?
    }

    function deposit() external payable virtual {
        _deposit(msg.sender, msg.value);
    }

    function _withdraw(address account_) internal virtual {
        require(!_isBlackoutPeriod(), "RevenueSplitter::_withdraw: BLACKOUT_PERIOD");
        require(lastPeriodRevenue > 0, "RevenueSplitter::_withdraw: ZERO_REVENUE");

        uint256 withdrawlPower = _getCurWithdrawlPower(account_);

        require(withdrawlPower > 0, "RevenueSplitter::_withdraw: ZERO_WITHDRAWL_POWER");

        // TODO will this work w/ miniscule shares?
        uint256 share = (withdrawlPower * 1000) / totalSupply();
        uint256 ethShare = share * (lastPeriodRevenue / 1000);

        withdrawlReceipts[curPeriodId - 1][account_] += withdrawlPower;
        (bool success, ) = account_.call{ value: ethShare }("");
        require(success, "RevenueSplitter::_withdrawRevenueShare: REQUEST_FAILED");
        // TODO handle bytes error message
        // TODO emit event
    }

    function withdraw() external virtual {
        _withdraw(msg.sender);
    }

    function withdrawBySig(
        uint256 revenuePeriodDate_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external {
        require(revenuePeriodDate_ == lastPeriodDate, "RevenueSplitter::withdrawBySig: INVALID_REVENUE_PERIOD_DATE");

        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
        );
        bytes32 structHash = keccak256(abi.encode(REVENUE_PERIOD_DATE_TYPEHASH, revenuePeriodDate_));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v_, r_, s_);

        require(signer != address(0), "RevenueSplitter::withdrawBySig: INVALID_SIGNATURE");

        _withdraw(signer);
    }

    function withdrawBulk(
        uint256[] calldata datesList_,
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external {
        require(datesList_.length == vList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_V_LIST");
        require(datesList_.length == rList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_R_LIST");
        require(datesList_.length == sList_.length, "RevenueSplitter::withdrawBulk: INFORMATION_ARITY_MISMATCH_S_LIST");

        for (uint256 i = 0; i < vList_.length; i++) {
            address(this).call(
                abi.encodeWithSignature(
                    "withdrawBySig(uint256,uint8,bytes32,bytes32)",
                    datesList_[i],
                    vList_[i],
                    rList_[i],
                    sList_[i]
                )
            );
        }
    }

    function _redeem(address account_) internal virtual {
        RestrictedTokenGrant[] storage tokenGrants = _tokenGrants[account_];

        require(tokenGrants.length > 0, "RevenueSplitter::redeem: ZERO_TOKEN_PURCHASES");

        uint256 exercisedTokensCount;
        for (uint256 i = 0; i < tokenGrants.length; i++) {
            if (tokenGrants[i].vestingPeriod <= curPeriodId && !tokenGrants[i].exercised) {
                tokenGrants[i].exercised = true;
                exercisedTokensCount += tokenGrants[i].amount;
            }
        }

        require(exercisedTokensCount > 0, "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES");

        _totalSupplyUnexercised -= exercisedTokensCount;
        _mint(account_, exercisedTokensCount);

        emit Redeem(account_, curPeriodId, exercisedTokensCount);
    }

    function redeem() external virtual {
        _redeem(msg.sender);
    }

    function redeemBySig(
        uint256 revenuePeriodDate_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external {
        require(revenuePeriodDate_ == lastPeriodDate, "RevenueSplitter::redeemBySig: INVALID_REVENUE_PERIOD_DATE");

        bytes32 domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this))
        );
        bytes32 structHash = keccak256(abi.encode(REVENUE_PERIOD_DATE_TYPEHASH, revenuePeriodDate_));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v_, r_, s_);

        require(signer != address(0), "RevenueSplitter::redeemBySig: INVALID_SIGNATURE");

        _redeem(signer);
    }

    function redeemBulk(
        uint256[] calldata datesList_,
        uint8[] calldata vList_,
        bytes32[] calldata rList_,
        bytes32[] calldata sList_
    ) external {
        require(datesList_.length == vList_.length, "RevenueSplitter::redeemBulk: INFORMATION_ARITY_MISMATCH_V_LIST");
        require(datesList_.length == rList_.length, "RevenueSplitter::redeemBulk: INFORMATION_ARITY_MISMATCH_R_LIST");
        require(datesList_.length == sList_.length, "RevenueSplitter::redeemBulk: INFORMATION_ARITY_MISMATCH_S_LIST");

        for (uint256 i = 0; i < vList_.length; i++) {
            address(this).call(
                abi.encodeWithSignature(
                    "redeemBySig(uint256,uint8,bytes32,bytes32)",
                    datesList_[i],
                    vList_[i],
                    rList_[i],
                    sList_[i]
                )
            );
        }
    }

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
        amount = balanceOf(account_) - withdrawlReceipts[curPeriodId - 1][account_];
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

        withdrawlReceipts[curPeriodId - 1][to_] += withdrawlReceiptTransfer;
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
    //         _createTokenGrant(to_, curPeriodId + 2, amount_);
    //     }

    //     _totalSupply[id_] += amount_;

    //     super._mint(to_, id_, amount_, data_);
    // }

    function _setCurPeriod(
        uint256 date_,
        uint256 revenue_,
        uint256 totalSupply_
    ) internal {
        curPeriodDate = date_;
        curPeriodRevenue = revenue_;
        curPeriodTotalSupply = totalSupply_;
    }

    function _setLastPeriod(
        uint256 date_,
        uint256 revenue_,
        uint256 totalSupply_
    ) internal {
        lastPeriodDate = date_;
        lastPeriodRevenue = revenue_;
        lastPeriodTotalSupply = totalSupply_;
    }

    function endPeriod() public {
        require(block.timestamp >= curPeriodDate, "RevenueSplitter::endPeriod: REVENUE_PERIOD_IN_PROGRESS");

        _beforeEndPeriod();

        // Write to memory in order to avoid reading from storage more than once
        // Prevent setting `lastPeriodRevenue` to an amount greater than the contract owns
        uint256 endingPeriodRevenue = curPeriodRevenue > address(this).balance
            ? address(this).balance
            : curPeriodRevenue;
        uint256 endingPeriodTotalSupply = curPeriodTotalSupply;
        _setLastPeriod(curPeriodDate, endingPeriodRevenue, endingPeriodTotalSupply);

        uint256 startingPeriodDate = block.timestamp + REVENUE_PERIOD_DURATION;
        uint256 startingPeriodId = curPeriodId + 1;

        _setCurPeriod(startingPeriodDate, endingPeriodRevenue, endingPeriodTotalSupply);
        curPeriodId = startingPeriodId;

        _afterEndPeriod();

        emit StartPeriod(startingPeriodId, startingPeriodDate, endingPeriodRevenue, endingPeriodTotalSupply);
    }

    function execute(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata calldatas
    ) external {
        require(msg.sender == owner, "RevenuePool::execute: ONLY_OWNER");

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returndata) = targets[i].call{ value: values[i] }(calldatas[i]);
            if (success) {
                emit Execute(targets[i], values[i], calldatas[i]);
            } else if (returndata.length > 0) {
                // From OZ's Address.sol contract
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                // No revert reason given
                revert("RevenuePool::execute: CALL_REVERTED_WITHOUT_MESSAGE");
            }
        }
    }

    receive() external payable {
        _onReceive();
        curPeriodRevenue += msg.value;
        emit PaymentReceived(msg.sender, msg.value);
    }

    // TODO setGuardian()

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

    function _beforeEndPeriod() internal virtual {}

    function _afterEndPeriod() internal virtual {}

    // function _beforeExecute(bytes calldata data_) internal virtual {
    //     console.log("PLACEHOLDER");
    // }

    // function _afterExecute(bytes calldata data_) internal virtual {
    //     console.log("PLACEHOLDER");
    // }

    function _onReceive() internal virtual {}

    event PaymentReceived(address, uint256);

    event Redeem(address, uint256, uint256);

    // TODO necessary to index `endingPeriodDate`? Check gas cost of indexing.
    event StartPeriod(
        uint256 indexed revenuePeriodId,
        uint256 indexed revenuePeriodDate,
        uint256 revenuePeriodPool,
        uint256 revenuePeriodTotalSupply
    );

    event Execute(address indexed target, uint256 value, bytes);
}
