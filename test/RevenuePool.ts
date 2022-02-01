import { artifacts, ethers, waffle, network } from "hardhat";
import type { Artifact } from "hardhat/types";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import type { RevenuePool } from "../src/types/RevenuePool";

import { expect } from "chai";
import { BigNumber } from "ethers";

const { utils } = ethers;
const { parseEther } = utils;
const { provider } = waffle;

const ZERO_ETH = BigNumber.from(0);
const ONE_ETH = parseEther("1");
const TWO_ETH = parseEther("2");
const REVENUE_PERIOD = 1000 * 60 * 60 * 90; // 90 days
const ONE_DAY = 1000 * 60 * 60;
const TOKEN_ID = BigNumber.from(1);
const TOKEN_OPTION_ID = BigNumber.from(2);

const purchaseTokens = async (pool: RevenuePool, accounts: SignerWithAddress[], amount: BigNumber) => {
  for (let i = 0; i < accounts.length; i++) {
    await pool.connect(accounts[i]).deposit({ value: amount });
  }
};

const jumpRevenuePeriods = async (pool: RevenuePool, n: number) => {
  for (let i = 0; i < n; i++) {
    await network.provider.send("evm_increaseTime", [REVENUE_PERIOD + ONE_DAY]);
    await pool.endRevenuePeriod();
  }
};

describe("Unit Tests Tests", () => {
  let pool: RevenuePool;
  let signers: SignerWithAddress[];
  let [admin, account1, account2]: SignerWithAddress[] = [];

  before(async function () {
    signers = await ethers.getSigners();
    [admin, account1, account2] = signers;
    signers = signers.slice(1);
  });

  describe("RevenuePool", () => {
    beforeEach(async () => {
      const revenuePoolArtifact: Artifact = await artifacts.readArtifact("RevenuePool");
      pool = <RevenuePool>(
        await waffle.deployContract(admin, revenuePoolArtifact, [
          admin.address,
          parseEther("100"),
          1,
          "Web3 Revenue Pool",
          "WRP",
        ])
      );
    });

    describe("deposit", () => {
      it("Should purchase tokens during the first liquidity period", async () => {
        await pool.connect(account1).deposit({ value: TWO_ETH });

        // expect equivalent token balance and zero token share balance
        // console.log("BALANCE: ", await pool.balanceOf(account1.address));
        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });

      it("Should purchase token shares after the first liquidity period", async () => {
        // jump to 2nd liquidity period
        await jumpRevenuePeriods(pool, 1);

        await pool.connect(account1).deposit({ value: TWO_ETH });

        expect(await pool.balanceOf(account1.address)).to.equal(ZERO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(TWO_ETH);
      });

      it("Should fail if token purchase exceeds max token supply", async () => {
        // TODO implement
        // use signers to purchase ~95 tokens
        // use singer to purchase 6 tokens, expect revert
      });

      it("Should fail if token option purchase exceeds max token supply", async () => {
        // TODO implement
        // use signers to purchase ~60 tokens
        // use signers to purchase ~35 token options
        // use singer to purchase 6 tokens options, expect revert
      });
    });

    describe("withdraw", () => {
      beforeEach(async () => {
        // TODO reduce signer count from 10 to 5
        await purchaseTokens(pool, signers.slice(0, 10), TWO_ETH);
      });
      //  - can withdraw correct amount
      it("Should withdraw the correct amount", async () => {
        await admin.sendTransaction({
          to: pool.address,
          value: parseEther("9"),
        });

        await jumpRevenuePeriods(pool, 1);

        const balanceBeforeWithdrawl: BigNumber = await account1.getBalance();

        await pool.connect(account1).withdraw();

        const balanceAfterWithdrawl: BigNumber = await account1.getBalance();

        const amountWithdrawn = balanceAfterWithdrawl.sub(balanceBeforeWithdrawl);

        // Should be 0.9 ETH less gas fees for executing withdraw()
        expect(amountWithdrawn).gte(parseEther("0.899"));
      });
      //  - cannot withdraw, transfer tokens, withraw again using same tokens
      // it("Should prevent tokens being used to withdraw more than once in a given period", () => {});
    });

    describe.only("withdrawBySig", () => {
      it("Should fail due to INVALID_REVENUE_PERIOD_DATE", async () => {
        const types = {
          LastRevenuePeriod: [{ name: "date", type: "uint256" }],
        };
        const domain = {
          name: "Web3 Revenue Pool",
          chainId: (await provider.getNetwork()).chainId, // get chain id from ethers
          verifyingContract: pool.address, // contract address
        };

        const filters = pool.filters.StartPeriod();
        const curPeriod = (await pool.queryFilter(filters))[0];
        const lastRevenuePeriodDate = curPeriod.args.revenuePeriodDate;

        await purchaseTokens(pool, [account1], TWO_ETH);

        const message = { date: lastRevenuePeriodDate };
        const signature = await account1._signTypedData(domain, types, message);
        const { v, r, s } = ethers.utils.splitSignature(signature);

        // Jumping 2 revenue periods will invalidate withdrawl requests from the
        // `lastRevenuePeriodDate` revenue period because that time stamp no longer the
        // represents the most recently ended revenue period.
        await jumpRevenuePeriods(pool, 2);
        await expect(pool.withdrawBySig(lastRevenuePeriodDate, v, r, s)).to.be.revertedWith(
          "RevenueSplitter::withdrawBySig: INVALID_REVENUE_PERIOD_DATE",
        );
      });
    });

    describe("withdrawBulk", () => {
      const signatures: string[] = [];

      it("Should withdraw for several accounts", async () => {
        const types = {
          LastRevenuePeriod: [{ name: "date", type: "uint256" }],
        };
        const domain = {
          name: "Web3 Revenue Pool",
          chainId: (await provider.getNetwork()).chainId, // get chain id from ethers
          verifyingContract: pool.address, // contract address
        };

        // Get first "StartPeriod" event
        const filters = pool.filters.StartPeriod();
        const curPeriod = (await pool.queryFilter(filters))[0];
        const lastRevenuePeriodDate = curPeriod.args.revenuePeriodDate;
        const _signers = signers.slice(0, 6);

        // Last signer is not to be a valid owner of LP tokens
        await purchaseTokens(pool, _signers.slice(0, 5), TWO_ETH);
        const message = { date: lastRevenuePeriodDate };

        for (let i = 0; i < _signers.length; i++) {
          signatures.push(await _signers[i]._signTypedData(domain, types, message));
        }

        const balancesBeforeWithrawl: BigNumber[] = [];
        for (let i = 0; i < _signers.length; i++) {
          balancesBeforeWithrawl.push(await _signers[i].getBalance());
        }

        const periodDateList: BigNumber[] = [];
        const vList: any[] = [];
        const rList: any[] = [];
        const sList: any[] = [];

        signatures.forEach((sig: any) => {
          periodDateList.push(lastRevenuePeriodDate);
          const { v, r, s } = ethers.utils.splitSignature(sig);
          vList.push(v);
          rList.push(r);
          sList.push(s);
        });

        await admin.sendTransaction({
          to: pool.address,
          value: parseEther("10"),
        });

        await jumpRevenuePeriods(pool, 1);

        await pool.withdrawBulk(periodDateList, vList, rList, sList);

        const balancesAfterWithrawl: BigNumber[] = [];
        for (let i = 0; i < _signers.length; i++) {
          balancesAfterWithrawl.push(await _signers[i].getBalance());
        }

        const expectedBalancesAfterWithdrawl = balancesBeforeWithrawl.map((balance, idx) => {
          // Only expect an increased balance for the first n - 1 wallets
          if (idx < balancesBeforeWithrawl.length - 1) {
            return balance.add(TWO_ETH);
          }
          return balance;
        });

        expect(balancesAfterWithrawl).to.deep.equals(expectedBalancesAfterWithdrawl);
      });
    });

    describe("redeem", () => {
      // beforeEach(async () => {
      // });

      it("Should fail if options haven't been purchased", async () => {
        await expect(pool.connect(account1).redeem()).to.be.revertedWith(
          "RevenueSplitter::redeem: ZERO_TOKEN_PURCHASES",
        );
      });

      it("Should fail if options haven't vested yet", async () => {
        // jump to 2nd liquidity period
        await jumpRevenuePeriods(pool, 1);

        // purchase token options
        await purchaseTokens(pool, signers, TWO_ETH);

        await expect(pool.connect(account1).redeem()).to.be.revertedWith(
          "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES",
        );
      });

      // Should only exercise unexercised vested tokens
      it("Should only exercise unexercised vested tokens", async () => {
        // jump to 2nd liquidity period
        await jumpRevenuePeriods(pool, 1);

        // purchase token options
        await purchaseTokens(pool, signers, TWO_ETH);

        // jump to 4th liquidity period
        // where purchased token shares can be exercised
        await jumpRevenuePeriods(pool, 2);

        expect(await pool.balanceOf(account1.address)).to.equal(ZERO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(TWO_ETH);

        await pool.connect(account1).redeem();

        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });

      it("Should work with 10 purchase records over time", async () => {
        // repeat n times
        // increase `n` in order to see how much `redeem()` costs as
        // the number of token purchases for a given user scales
        const n = 20;
        await jumpRevenuePeriods(pool, 1);
        for (let i = 0; i < n; i++) {
          await purchaseTokens(pool, [account1], TWO_ETH);
          await jumpRevenuePeriods(pool, 2);
          await pool.connect(account1).redeem();
        }

        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH.mul(n));
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });
      // Should throw an error if no unexercised vested tokens
    });

    // TODO test tsx fees

    // TODO test exchange rate
  });
});
