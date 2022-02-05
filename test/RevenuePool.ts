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
const REVENUE_PERIOD = 1000 * 60 * 60 * 30; // 30 days
const BLACKOUT_PERIOD = 1000 * 60 * 60 * 3; // 3 days
const ONE_DAY = 1000 * 60 * 60;
const TOKEN_ID = BigNumber.from(1);
const TOKEN_OPTION_ID = BigNumber.from(2);

const purchaseTokens = async (pool: RevenuePool, accounts: SignerWithAddress[], amount: BigNumber) => {
  for (let i = 0; i < accounts.length; i++) {
    await pool.connect(accounts[i]).deposit({ value: amount });
  }
};

const jumpPeriods = async (pool: RevenuePool, n: number, skipBlackout?: boolean) => {
  let blackoutDuration;

  for (let i = 0; i < n; i++) {
    blackoutDuration = skipBlackout && i == n - 1 ? BLACKOUT_PERIOD : 0;

    await network.provider.send("evm_increaseTime", [REVENUE_PERIOD + ONE_DAY]);
    await pool.endPeriod();
    if (blackoutDuration) {
      await network.provider.send("evm_increaseTime", [blackoutDuration]);
    }
  }
};

describe("Unit Tests Tests", () => {
  let pool: RevenuePool;
  let signers: SignerWithAddress[];
  let [admin, account1, account2, account3]: SignerWithAddress[] = [];

  before(async function () {
    signers = await ethers.getSigners();
    [admin, account1, account2, account3] = signers;
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
        await jumpPeriods(pool, 1);

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

    describe.only("withdraw", () => {
      let balanceBeforeWithdrawl: BigNumber;
      beforeEach(async () => {
        // TODO reduce signer count from 10 to 5
        await purchaseTokens(pool, signers.slice(0, 5), TWO_ETH);
        await admin.sendTransaction({
          to: pool.address,
          value: parseEther("5"),
        });

        await jumpPeriods(pool, 1, true);

        balanceBeforeWithdrawl = await account1.getBalance();
      });
      //  - can withdraw correct amount
      it("Should withdraw the correct amount", async () => {
        await pool.connect(account1).withdraw();

        const balanceAfterWithdrawl: BigNumber = await account1.getBalance();

        const amountWithdrawn = balanceAfterWithdrawl.sub(balanceBeforeWithdrawl);

        // Should be 1 ETH less gas fees
        expect(amountWithdrawn).gte(parseEther("0.999"));
        expect(amountWithdrawn).lt(parseEther("1"));
      });

      it("Withdrawing tokens more than once in a given period should result in a 'ZERO_WITHDRAWL_POWER' error", async () => {
        await pool.connect(account1).withdraw();
        await expect(pool.connect(account1).withdraw()).to.be.revertedWith(
          "RevenueSplitter::_withdraw: ZERO_WITHDRAWL_POWER",
        );
      });

      it("Should prevent tokens being used to withdraw after being withdrawn and then transfered", async () => {
        await pool.connect(account1).withdraw();
        // Transfer token withdrawn this period
        await pool.connect(account1).transfer(account2.address, ONE_ETH);

        balanceBeforeWithdrawl = await account2.getBalance();
        await pool.connect(account2).withdraw();

        let balanceAfterWithdrawl: BigNumber = await account2.getBalance();
        let amountWithdrawn = balanceAfterWithdrawl.sub(balanceBeforeWithdrawl);

        expect(amountWithdrawn).gte(parseEther("0.999"));
        expect(amountWithdrawn).lt(parseEther("1"));

        // Transfer token not yet withdrawn this period
        await pool.connect(account3).transfer(account2.address, TWO_ETH);

        await pool.connect(account2).withdraw();
        balanceAfterWithdrawl = await account2.getBalance();
        amountWithdrawn = balanceAfterWithdrawl.sub(balanceBeforeWithdrawl);

        expect(amountWithdrawn).gte(parseEther("1.999"));
        expect(amountWithdrawn).lt(parseEther("2.0"));

        // account3 is expected to not be able to withdraw any revenue share
        // because they transfered all of their shares
        await expect(pool.connect(account3).withdraw()).to.be.revertedWith(
          "RevenueSplitter::_withdraw: ZERO_WITHDRAWL_POWER",
        );
      });
    });

    describe("withdrawBySig", () => {
      it("Should fail due to INVALID_REVENUE_PERIOD_DATE", async () => {
        const types = {
          LastPeriod: [{ name: "date", type: "uint256" }],
        };
        const domain = {
          name: "Web3 Revenue Pool",
          chainId: (await provider.getNetwork()).chainId, // get chain id from ethers
          verifyingContract: pool.address, // contract address
        };

        const filters = pool.filters.StartPeriod();
        const curPeriod = (await pool.queryFilter(filters))[0];
        const lastPeriodDate = curPeriod.args.revenuePeriodDate;

        await purchaseTokens(pool, [account1], TWO_ETH);

        const message = { date: lastPeriodDate };
        const signature = await account1._signTypedData(domain, types, message);
        const { v, r, s } = ethers.utils.splitSignature(signature);

        // Jumping 2 revenue periods will invalidate withdrawl requests from the
        // `lastPeriodDate` revenue period because that time stamp no longer the
        // represents the most recently ended revenue period.
        await jumpPeriods(pool, 2, true);
        await expect(pool.withdrawBySig(lastPeriodDate, v, r, s)).to.be.revertedWith(
          "RevenueSplitter::withdrawBySig: INVALID_REVENUE_PERIOD_DATE",
        );
      });
    });

    describe("withdrawBulk", () => {
      const signatures: string[] = [];

      it("Should withdraw for several accounts", async () => {
        // Get first "StartPeriod" event
        const filters = pool.filters.StartPeriod();
        const curPeriod = (await pool.queryFilter(filters))[0];
        const lastPeriodDate = curPeriod.args.revenuePeriodDate;
        const _signers = signers.slice(0, 6);

        // Last signer is not to be a valid owner of LP tokens
        await purchaseTokens(pool, _signers.slice(0, 5), TWO_ETH);

        const types = {
          LastPeriod: [{ name: "date", type: "uint256" }],
        };
        const domain = {
          name: "Web3 Revenue Pool",
          chainId: (await provider.getNetwork()).chainId, // get chain id from ethers
          verifyingContract: pool.address, // contract address
        };
        const message = { date: lastPeriodDate };

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
          periodDateList.push(lastPeriodDate);
          const { v, r, s } = ethers.utils.splitSignature(sig);
          vList.push(v);
          rList.push(r);
          sList.push(s);
        });

        await admin.sendTransaction({
          to: pool.address,
          value: parseEther("10"),
        });

        await jumpPeriods(pool, 1, true);

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

        expect(balancesAfterWithrawl).to.deep.equal(expectedBalancesAfterWithdrawl);
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
        await jumpPeriods(pool, 1);

        // purchase token options
        await purchaseTokens(pool, signers, TWO_ETH);

        await expect(pool.connect(account1).redeem()).to.be.revertedWith(
          "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES",
        );
      });

      // Should only exercise unexercised vested tokens
      it("Should only exercise unexercised vested tokens", async () => {
        // jump to 2nd liquidity period
        await jumpPeriods(pool, 1);

        // purchase token options
        await purchaseTokens(pool, signers, TWO_ETH);

        // jump to 4th liquidity period
        // where purchased token shares can be exercised
        await jumpPeriods(pool, 2);

        expect(await pool.balanceOf(account1.address)).to.equal(ZERO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(TWO_ETH);

        await pool.connect(account1).redeem();

        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });

      /**
       * This is a stress test to insure that `redeem()` scales well as
       * the number of token purchases (list items) increases.
       */
      it("Should work with 10 purchase records over time", async () => {
        const n = 10;
        // Unexercised tokens cannot be purchased in the 1st revenue period.
        await jumpPeriods(pool, 1);

        for (let i = 0; i < n; i++) {
          await purchaseTokens(pool, [account1], TWO_ETH);
          await jumpPeriods(pool, 2);
          await pool.connect(account1).redeem();
        }

        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH.mul(n));
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });
      // TODO Should throw an error if no unexercised vested tokens
    });

    // TODO skip?
    describe("redeemBySig", () => {
      // it("Should fail due to INVALID_REVENUE_PERIOD_DATE", async () => {});
    });

    describe("redeemBulk", () => {
      it("Should redeem for several accounts", async () => {
        const _signers = signers.slice(0, 6);
        const signatures: string[] = [];

        // Unexercised tokens cannot be purchased in the 1st revenue period.
        await jumpPeriods(pool, 1);

        // Last signer is not to be a valid owner of Unexercised Tokens
        await purchaseTokens(pool, _signers.slice(0, 5), TWO_ETH);

        // jump to 4th liquidity period
        // where purchased token shares can be exercised
        await jumpPeriods(pool, 1);

        const filters = pool.filters.StartPeriod();
        const curPeriod = (await pool.queryFilter(filters))[2];
        const curPeriodDate = curPeriod.args.revenuePeriodDate;

        await jumpPeriods(pool, 1);

        const types = {
          LastPeriod: [{ name: "date", type: "uint256" }],
        };
        const domain = {
          name: "Web3 Revenue Pool",
          chainId: (await provider.getNetwork()).chainId, // get chain id from ethers
          verifyingContract: pool.address, // contract address
        };
        const message = { date: curPeriodDate };

        for (let i = 0; i < _signers.length; i++) {
          signatures.push(await _signers[i]._signTypedData(domain, types, message));
        }

        const periodDateList: BigNumber[] = [];
        const vList: any[] = [];
        const rList: any[] = [];
        const sList: any[] = [];

        signatures.forEach((sig: any) => {
          periodDateList.push(curPeriodDate);
          const { v, r, s } = ethers.utils.splitSignature(sig);
          vList.push(v);
          rList.push(r);
          sList.push(s);
        });

        await pool.redeemBulk(periodDateList, vList, rList, sList);

        const actualBalances: BigNumber[] = [];
        for (let i = 0; i < _signers.length; i++) {
          actualBalances.push(await pool.balanceOf(_signers[i].address));
        }

        const expectedBalances = [TWO_ETH, TWO_ETH, TWO_ETH, TWO_ETH, TWO_ETH, ZERO_ETH];

        /**
         * Placing the `expect`s in a loop to bypass a bug with Chai.
         * `expect(actualBalances).to.deep.equals(expectedBalances)` doesn't work while method does.
         */
        _signers.forEach((_, idx) => {
          expect(actualBalances[idx]).to.deep.equal(expectedBalances[idx]);
        });
      });
    });

    // TODO test tsx fees

    // TODO test exchange rate
  });
});
