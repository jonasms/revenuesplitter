import { artifacts, ethers, waffle, network } from "hardhat";
import type { Artifact } from "hardhat/types";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import type { RevenuePool } from "../src/types/RevenuePool";

import { expect } from "chai";
import { BigNumber } from "ethers";

const { utils } = ethers;
const { parseEther } = utils;

const ZERO_ETH = BigNumber.from(0);
const ONE_ETH = parseEther("1");
const TWO_ETH = parseEther("2");
const LIQUIDITY_PERIOD = 1000 * 60 * 60 * 90; // 90 days
const ONE_DAY = 1000 * 60 * 60;
const TOKEN_ID = BigNumber.from(1);
const TOKEN_OPTION_ID = BigNumber.from(2);

const purchaseTokens = async (pool: RevenuePool, accounts: SignerWithAddress[], amount: BigNumber) => {
  for (let i = 0; i < accounts.length; i++) {
    await pool.connect(accounts[i]).deposit({ value: amount });
  }
};

const jumpLiquidityPeriods = async (pool: RevenuePool, n: number) => {
  for (let i = 0; i < n; i++) {
    await network.provider.send("evm_increaseTime", [LIQUIDITY_PERIOD + ONE_DAY]);
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
        // deposit ETH
        await pool.connect(account1).deposit({ value: TWO_ETH });

        // expect equivalent token balance and zero token share balance
        // console.log("BALANCE: ", await pool.balanceOf(account1.address));
        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH);
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });

      it("Should purchase token shares after the first liquidity period", async () => {
        // jump to 2nd liquidity period
        await jumpLiquidityPeriods(pool, 1);

        await pool.connect(account1).deposit({ value: TWO_ETH });

        // expect(await pool.connect(account1).balanceOf(account1.address, TOKEN_ID)).to.equal(ZERO_ETH);
        // expect(await pool.connect(account1).balanceOf(account1.address, TOKEN_OPTION_ID)).to.equal(TWO_ETH);

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
        await jumpLiquidityPeriods(pool, 1);

        // purchase token options
        await purchaseTokens(pool, signers, TWO_ETH);

        await expect(pool.connect(account1).redeem()).to.be.revertedWith(
          "RevenueSplitter::redeem: ZERO_EXERCISABLE_SHARES",
        );
      });

      // Should only exercise unexercised vested tokens
      it("Should only exercise unexercised vested tokens", async () => {
        // jump to 2nd liquidity period
        await jumpLiquidityPeriods(pool, 1);

        // purchase token options
        await purchaseTokens(pool, signers, TWO_ETH);

        // jump to 4th liquidity period
        // where purchased token shares can be exercised
        await jumpLiquidityPeriods(pool, 2);

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
        await jumpLiquidityPeriods(pool, 1);
        for (let i = 0; i < n; i++) {
          await purchaseTokens(pool, [account1], TWO_ETH);
          await jumpLiquidityPeriods(pool, 2);
          await pool.connect(account1).redeem();
        }

        expect(await pool.balanceOf(account1.address)).to.equal(TWO_ETH.mul(n));
        expect(await pool.balanceOfUnexercised(account1.address)).to.equal(ZERO_ETH);
      });
      // Should throw an error if no unexercised vested tokens
    });
  });
});
