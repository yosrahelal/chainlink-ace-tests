#!/usr/bin/env node

/**
 * Automates verification of the ACE deployment output produced by
 * `script/DeployAceStandardERC20.s.sol`.
 *
 * Usage:
 *   CHAIN_ID=3875 VERIFIER=blockscout VERIFIER_URL=https://explorer/api \
 *   node scripts/verify-ace.js
 *
 * Required env:
 *   - CHAIN_ID:            chain id used in the broadcast folder.
 *   - VERIFIER (optional): etherscan | blockscout (default: blockscout).
 *   - VERIFIER_URL:        required when using blockscout/custom explorers.
 *   - ETHERSCAN_API_KEY:   required when VERIFIER=etherscan.
 *   - BROADCAST_DIR:       override broadcast root (default: broadcast).
 *   - VERIFY_TARGETS:      optional CSV of contract names to include.
 *   - DRY_RUN=true         prints commands without executing forge.
 */

const fs = require("fs");
const path = require("path");
const {spawnSync} = require("child_process");

const CONTRACT_FQNS = {
  PolicyEngine: "packages/policy-management/src/core/PolicyEngine.sol:PolicyEngine",
  IdentityRegistry: "packages/cross-chain-identity/src/IdentityRegistry.sol:IdentityRegistry",
  CredentialRegistry: "packages/cross-chain-identity/src/CredentialRegistry.sol:CredentialRegistry",
  OnlyOwnerPolicy: "packages/policy-management/src/policies/OnlyOwnerPolicy.sol:OnlyOwnerPolicy",
  CredentialRegistryIdentityValidatorPolicy:
    "packages/cross-chain-identity/src/CredentialRegistryIdentityValidatorPolicy.sol:CredentialRegistryIdentityValidatorPolicy",
  AceStandardERC20: "packages/tokens/erc-20/src/AceStandardERC20.sol:AceStandardERC20",
  ERC20TransferExtractor:
    "packages/policy-management/src/extractors/ERC20TransferExtractor.sol:ERC20TransferExtractor",
  ERC1967Proxy: "node_modules/@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
};

const chainId = process.env.CHAIN_ID || "31337";
const broadcastDir = process.env.BROADCAST_DIR || "broadcast";
const broadcastFile = path.join(
  broadcastDir,
  "DeployAceStandardERC20.s.sol",
  chainId,
  "run-latest.json"
);

if (!fs.existsSync(broadcastFile)) {
  console.error(`✖ Broadcast file not found: ${broadcastFile}`);
  process.exit(1);
}

const verifier = process.env.VERIFIER || "blockscout";
const verifierUrl = process.env.VERIFIER_URL;
const etherscanKey = process.env.ETHERSCAN_API_KEY;
const compilerVersion = process.env.VERIFY_SOLC_VERSION || "v0.8.26+commit.4ed2d91f";
const optimizerRuns = process.env.VERIFY_OPTIMIZER_RUNS || "8000";
const dryRun = /^true$/i.test(process.env.DRY_RUN || "");

if (verifier === "blockscout" && !verifierUrl) {
  console.error("✖ VERIFIER_URL is required when VERIFIER=blockscout");
  process.exit(1);
}

if (verifier === "etherscan" && !etherscanKey) {
  console.error("✖ ETHERSCAN_API_KEY is required when VERIFIER=etherscan");
  process.exit(1);
}

const allowedTargets = process.env.VERIFY_TARGETS
  ? new Set(process.env.VERIFY_TARGETS.split(",").map((s) => s.trim()))
  : null;

const broadcast = JSON.parse(fs.readFileSync(broadcastFile, "utf8"));

const logicByAddress = new Map();
const implementationTxs = [];
const proxyTxs = [];

for (const tx of broadcast.transactions || []) {
  if (tx.transactionType !== "CREATE" || !tx.contractAddress) continue;

  const name = tx.contractName;
  if (!name) continue;

  if (name === "ERC1967Proxy") {
    proxyTxs.push(tx);
    continue;
  }

  if (!CONTRACT_FQNS[name]) continue;
  if (allowedTargets && !allowedTargets.has(name)) continue;

  const addressKey = tx.contractAddress.toLowerCase();
  if (!logicByAddress.has(addressKey)) {
    logicByAddress.set(addressKey, name);
    implementationTxs.push(tx);
  }
}

const targets = [];

for (const tx of implementationTxs) {
  const name = tx.contractName;
  targets.push({
    label: name,
    address: tx.contractAddress,
    fqName: CONTRACT_FQNS[name],
    type: "implementation"
  });
}

for (const tx of proxyTxs) {
  if (!tx.arguments || tx.arguments.length < 2) continue;
  const implAddr = String(tx.arguments[0]).toLowerCase();
  const initData = tx.arguments[1];
  const logicName = logicByAddress.get(implAddr);
  if (allowedTargets && logicName && !allowedTargets.has(logicName)) continue;

  targets.push({
    label: logicName ? `${logicName}Proxy` : "ERC1967Proxy",
    address: tx.contractAddress,
    fqName: CONTRACT_FQNS.ERC1967Proxy,
    type: "proxy",
    constructorArgs: [tx.arguments[0], initData]
  });
}

if (!targets.length) {
  console.error("✖ No verification targets found for the current broadcast file.");
  process.exit(1);
}

const baseArgs = [
  "verify-contract",
  "--verifier",
  verifier,
  "--chain-id",
  chainId,
  "--compiler-version",
  compilerVersion,
  "--num-of-optimizations",
  optimizerRuns
];

if (verifierUrl) {
  baseArgs.push("--verifier-url", verifierUrl);
}

if (etherscanKey) {
  baseArgs.push("--etherscan-api-key", etherscanKey);
}

function encodeProxyConstructorArgs(logic, data) {
  const cast = spawnSync(
    "cast",
    ["abi-encode", "constructor(address,bytes)", logic, data],
    {encoding: "utf8"}
  );
  if (cast.status !== 0) {
    console.error(cast.stderr);
    throw new Error("cast abi-encode failed");
  }
  return cast.stdout.trim();
}

for (const target of targets) {
  const args = [...baseArgs];
  args.push(target.address, target.fqName);

  if (target.type === "proxy") {
    const encodedArgs = encodeProxyConstructorArgs(
      target.constructorArgs[0],
      target.constructorArgs[1]
    );
    args.push("--constructor-args", encodedArgs);
  }

  const command = `forge ${args.join(" ")}`;
  console.log(`\n▶ ${target.label}: ${command}`);

  if (dryRun) continue;

  const result = spawnSync("forge", args, {stdio: "inherit"});
  if (result.status !== 0) {
    console.error(`✖ Verification failed for ${target.label} (${target.address})`);
    process.exit(result.status ?? 1);
  }
}

console.log("\n✔ Verification tasks completed.");
