// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {AceStandardERC20} from "../packages/tokens/erc-20/src/AceStandardERC20.sol";
import {IdentityRegistry} from "../packages/cross-chain-identity/src/IdentityRegistry.sol";
import {CredentialRegistry} from "../packages/cross-chain-identity/src/CredentialRegistry.sol";
import {IPolicyEngine} from "../packages/policy-management/src/interfaces/IPolicyEngine.sol";

/// @title DemoAceCompliance
/// @notice Broadcasts the four key transactions needed for the ACE compliance demo:
///         1. Mint tokens to the admin account.
///         2. Register identity + `common.KYC` credential for the compliant account.
///         3. Transfer succeeds once KYC is in place.
///         4. Attempt a transfer to a non-KYC account (and expect an on-chain revert).
contract DemoAceCompliance is Script {
  bytes32 internal constant COMMON_KYC = keccak256("common.KYC");

  function run() external {
    address deployer = vm.envAddress("DEPLOYER");
    uint256 deployerKey = vm.envUint("PRIVATE_KEY");
    address compliantAccount = vm.envAddress("COMPLIANT_ACCOUNT");
    address nonCompliantAccount = vm.envAddress("NONCOMPLIANT_ACCOUNT");

    AceStandardERC20 token = AceStandardERC20(vm.envAddress("ACE_TOKEN"));
    IdentityRegistry identityRegistry = IdentityRegistry(vm.envAddress("ACE_IDENTITY_REGISTRY"));
    CredentialRegistry credentialRegistry =
      CredentialRegistry(vm.envAddress("ACE_CREDENTIAL_REGISTRY"));
    address identityValidatorPolicy = vm.envAddress("ACE_IDENTITY_VALIDATOR_POLICY");

    bytes32 compliantCcid = _deriveCcid("COMPLIANT_CCID", compliantAccount);

    // Ensure the non-compliant address is clean so the failure is deterministic.
    _resetNonCompliantState(identityRegistry, credentialRegistry, deployerKey, nonCompliantAccount);

    // Step 1: Mint tokens to the deployer to fund the demo.
    vm.startBroadcast(deployerKey);
    token.mint(deployer, 10 ether);
    console.log("Step 1 -> Minted 10 tokens to the deployer (policy owner)");
    vm.stopBroadcast();

    // Step 2: Register identity + KYC credential for the compliant account.
    vm.startBroadcast(deployerKey);
    identityRegistry.registerIdentity(compliantCcid, compliantAccount, "");
    console.log("Step 2a -> Registered identity for compliant account");
    credentialRegistry.registerCredential(compliantCcid, COMMON_KYC, uint40(0), "", "");
    console.log("Step 2b -> Registered `common.KYC` credential for compliant account");
    vm.stopBroadcast();

    // Step 3: Transfer now succeeds.
    vm.startBroadcast(deployerKey);
    require(token.transfer(compliantAccount, 1 ether), "Compliant transfer reverted unexpectedly");
    vm.stopBroadcast();
    console.log("Step 3 -> Transfer to compliant account succeeded");

    // Step 4: Attempt transfer to a non-compliant account and expect a revert.
    bytes memory expectedError = abi.encodeWithSelector(
      IPolicyEngine.PolicyRunRejected.selector,
      token.transfer.selector,
      identityValidatorPolicy,
      "account identity validation failed"
    );
    vm.expectRevert(expectedError);
    vm.broadcast(deployerKey);
    token.transfer(nonCompliantAccount, 1 ether);
    console.log(
      "Step 4 -> Revert broadcast on-chain (PolicyRunRejected: account identity validation failed)"
    );
  }

  function _deriveCcid(string memory envKey, address account) internal returns (bytes32) {
    bytes32 provided = vm.envOr(envKey, bytes32(0));
    if (provided != bytes32(0)) {
      return provided;
    }

    string memory salt = vm.envOr("CCID_SALT", string(""));
    if (bytes(salt).length > 0) {
      return keccak256(abi.encodePacked(salt));
    }

    return keccak256(abi.encodePacked("ccid:", account));
  }

  function _resetNonCompliantState(
    IdentityRegistry identityRegistry,
    CredentialRegistry credentialRegistry,
    uint256 deployerKey,
    address nonCompliantAccount
  ) internal {
    bytes32 existingCcid = identityRegistry.getIdentity(nonCompliantAccount);
    if (existingCcid == bytes32(0)) {
      return;
    }

    console.log("Step 0 -> Clearing existing identity/credential for non-compliant account");
    vm.startBroadcast(deployerKey);

    // Best-effort removal; ignore failures if the credential is absent.
    try credentialRegistry.removeCredential(existingCcid, COMMON_KYC, "") {
      console.log("    Removed `common.KYC` credential from non-compliant account");
    } catch {}

    try identityRegistry.removeIdentity(existingCcid, nonCompliantAccount, "") {
      console.log("    Removed identity from non-compliant account");
    } catch {}

    vm.stopBroadcast();
  }
}
