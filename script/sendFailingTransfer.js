#!/usr/bin/env node
const { JsonRpcProvider, Wallet, Contract, parseEther } = require("ethers");
require("dotenv").config();

/**
 * Broadcasts a transfer that is expected to revert on-chain so the failure
 * appears in the explorer. The transaction is still sent, then we wait for
 * the receipt which should have status 0.
 */
async function main() {
  const provider = new JsonRpcProvider(process.env.RPC_URL);
  const wallet = new Wallet(process.env.PRIVATE_KEY, provider);

  const tokenAbi = ["function transfer(address to, uint256 amount) returns (bool)"];
  const token = new Contract(process.env.ACE_TOKEN, tokenAbi, wallet);

  console.log("Sending non-compliant transfer (expected to revert)...");

  const tx = await token.transfer.populateTransaction(
    process.env.NONCOMPLIANT_ACCOUNT,
    parseEther("1")
  );

  const txResponse = await wallet.sendTransaction({
    to: process.env.ACE_TOKEN,
    data: tx.data,
    gasLimit: 300000,
    gasPrice: 0
  });
  console.log("Transaction hash:", txResponse.hash);

  const receipt = await txResponse.wait();

  if (receipt.status === 0) {
    console.log("Transaction failed as expected.");
    console.log(receipt);
  } else {
    console.log("Unexpected success!");
    console.log(receipt);
  }
}

main().catch((err) => {
  console.error("Error sending failing transfer:", err);
  process.exit(1);
});
