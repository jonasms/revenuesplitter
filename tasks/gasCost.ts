import { task } from "hardhat/config";
import { BigNumber } from "ethers";

// @ts-ignore
import { setGasAndPriceRates } from "eth-gas-reporter/lib/utils";
import { string } from "hardhat/internal/core/params/argumentTypes";
// const { parseSoliditySources, setGasAndPriceRates } = require('eth-gas-reporter/lib/utils');

interface ReporterConfig {
  token: string;
  currency: string;
  coinmarketcap: string;
  gasPriceApi: string;
  gasPrice: number | undefined;
  ethPrice: number | undefined;
}

task("gas-cost", "Calculates the gas costs of a transaction")
  .addParam("gas", "amount of gas")
  .setAction(async (_taskArgs: any) => {
    const config: ReporterConfig = {
      token: "ETH",
      currency: "USD",
      coinmarketcap: "f3a244ee-0fb1-410b-85dc-8132cc3e59d5",
      gasPriceApi: "https://api.etherscan.io/api?module=proxy&action=eth_gasPrice",
      gasPrice: undefined,
      ethPrice: undefined,
    };
    /**
     * Gets the following properties:
     *  - ethPrice
     *  - gasPrice (gwei / gas)
     */
    await setGasAndPriceRates(config);
    const tsxCostGwei = _taskArgs.gas * config.gasPrice! * 10 ** 9;
    const tsxCostUSD = (tsxCostGwei * config.ethPrice!) / 10 ** 18;
    console.log("TSX COST: $", tsxCostUSD);
    console.log("gwei / gas: ", config.gasPrice);
    console.log("usd / eth : $", config.ethPrice);
  });
