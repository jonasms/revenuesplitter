import { artifacts, ethers, waffle, network } from "hardhat";
import type { Artifact } from "hardhat/types";
import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";

import type { RevenuePool } from "../src/types/RevenuePool";

import { expect } from "chai";
import { BigNumber as BigNumberType } from "ethers";

const { utils } = ethers;
const { parseEther } = utils;

const ONE_ETH = ethers.BigNumber.from(1);
const TWO_ETH = ethers.BigNumber.from(2);
const LIQUIDITY_PERIOD = 1000 * 60 * 60 * 90; // 90 days
const ONE_DAY = 1000 * 60 * 60;

const purchaseTokens = async (pool: RevenuePool, accounts: SignerWithAddress[], amount: BigNumberType) => {
  for (let i = 0; i < accounts.length; i++) {
    await pool.connect(accounts[i]).deposit({ value: amount });
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
    before(async () => {
      // await network.provider.send("evm_mine", [LIQUIDITY_PERIOD + ONE_DAY]);
    });

    beforeEach(async () => {
      const revenuePoolArtifact: Artifact = await artifacts.readArtifact("RevenuePool");
      pool = <RevenuePool>(
        await waffle.deployContract(admin, revenuePoolArtifact, [admin.address, "testpool.com/api/{id}.json"])
      );
    });

    describe("redeem", () => {
      before(async () => {
        await network.provider.send("evm_mine", [LIQUIDITY_PERIOD + ONE_DAY]);

        // purchase token shares
        await purchaseTokens(pool, signers, TWO_ETH);

        // fast forward time by 91 days
      });
      // Should only exercise unexercised vested tokens
      it("Should only exercise unexercised vested tokens", async () => {
        // skip to next liquidity period
        await network.provider.send("evm_mine", [LIQUIDITY_PERIOD + ONE_DAY]);
        // redeem
        await pool.connect(account1).redeem();
      });
      // Should throw an error if no unexercised vested tokens
    });
  });
});
