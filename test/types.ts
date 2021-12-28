import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import type { Fixture } from "ethereum-waffle";

import type { RevenueSplitter } from "../src/types/RevenueSplitter";
import type { RevenuePool } from "../src/types/RevenuePool";

declare module "mocha" {
  export interface Context {
    revenueSplitter: RevenueSplitter;
    reveuePool: RevenuePool;
    loadFixture: <T>(fixture: Fixture<T>) => Promise<T>;
    signers: Signers;
  }
}

export interface Signers {
  admin: SignerWithAddress;
}
