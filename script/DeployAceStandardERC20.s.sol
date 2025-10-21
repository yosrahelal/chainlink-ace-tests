// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.26;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

import {Policy} from "@chainlink/policy-management/core/Policy.sol";
import {PolicyEngine} from "@chainlink/policy-management/core/PolicyEngine.sol";
import {IPolicyEngine} from "@chainlink/policy-management/interfaces/IPolicyEngine.sol";
import {OnlyOwnerPolicy} from "@chainlink/policy-management/policies/OnlyOwnerPolicy.sol";
import {ERC20TransferExtractor} from "@chainlink/policy-management/extractors/ERC20TransferExtractor.sol";

import {IdentityRegistry} from "@chainlink/cross-chain-identity/IdentityRegistry.sol";
import {CredentialRegistry} from "@chainlink/cross-chain-identity/CredentialRegistry.sol";
import {CredentialRegistryIdentityValidatorPolicy} from
  "@chainlink/cross-chain-identity/CredentialRegistryIdentityValidatorPolicy.sol";
import {ICredentialRequirements} from "@chainlink/cross-chain-identity/interfaces/ICredentialRequirements.sol";

import {AceStandardERC20} from "../packages/tokens/erc-20/src/AceStandardERC20.sol";

/// @title DeployAceStandardERC20
/// @notice Full deployment walk-through for an ERC20 that integrates Chainlink ACE (Policy Engine + CCID).
/// @dev This script mirrors the steps explained in `getting_started/INTEGRER_ACE_ERC20.md`.
contract DeployAceStandardERC20 is Script {
  function run() external {
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    // Allow custom token metadata via environment variables.
    string memory tokenName = vm.envOr("TOKEN_NAME", string("ACE Token"));
    string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("ACE"));

    vm.startBroadcast(deployerPrivateKey);

    // ----------------------------------------------------------------------
    // 1. PolicyEngine deployment (behind a proxy) + governance baseline
    // ----------------------------------------------------------------------
    PolicyEngine policyEngineImplementation = new PolicyEngine();
    bytes memory policyEngineInitData =
      abi.encodeWithSelector(PolicyEngine.initialize.selector, true, deployer);
    ERC1967Proxy policyEngineProxy = new ERC1967Proxy(address(policyEngineImplementation), policyEngineInitData);
    PolicyEngine policyEngine = PolicyEngine(address(policyEngineProxy));

    // ----------------------------------------------------------------------
    // 2. Cross-Chain Identity registries (Identity + Credential) governed by ACE
    // ----------------------------------------------------------------------
    IdentityRegistry identityRegistryImplementation = new IdentityRegistry();
    bytes memory identityRegistryInitData =
      abi.encodeWithSelector(IdentityRegistry.initialize.selector, address(policyEngine), deployer);
    ERC1967Proxy identityRegistryProxy =
      new ERC1967Proxy(address(identityRegistryImplementation), identityRegistryInitData);
    IdentityRegistry identityRegistry = IdentityRegistry(address(identityRegistryProxy));

    CredentialRegistry credentialRegistryImplementation = new CredentialRegistry();
    bytes memory credentialRegistryInitData =
      abi.encodeWithSelector(CredentialRegistry.initialize.selector, address(policyEngine), deployer);
    ERC1967Proxy credentialRegistryProxy =
      new ERC1967Proxy(address(credentialRegistryImplementation), credentialRegistryInitData);
    CredentialRegistry credentialRegistry = CredentialRegistry(address(credentialRegistryProxy));

    // Restrict identity/credential management to the deployer via OnlyOwnerPolicy instances.
    OnlyOwnerPolicy identityAdminPolicyImpl = new OnlyOwnerPolicy();
    bytes memory identityAdminPolicyInitData =
      abi.encodeWithSelector(Policy.initialize.selector, address(policyEngine), deployer, new bytes(0));
    ERC1967Proxy identityAdminPolicyProxy =
      new ERC1967Proxy(address(identityAdminPolicyImpl), identityAdminPolicyInitData);
    OnlyOwnerPolicy identityAdminPolicy = OnlyOwnerPolicy(address(identityAdminPolicyProxy));

    // Attach the administrative policy to the registries' privileged functions.
    policyEngine.addPolicy(
      address(identityRegistry),
      IdentityRegistry.registerIdentity.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );
    policyEngine.addPolicy(
      address(identityRegistry),
      IdentityRegistry.registerIdentities.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );
    policyEngine.addPolicy(
      address(identityRegistry),
      IdentityRegistry.removeIdentity.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );
    policyEngine.addPolicy(
      address(credentialRegistry),
      CredentialRegistry.registerCredential.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );
    policyEngine.addPolicy(
      address(credentialRegistry),
      CredentialRegistry.registerCredentials.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );
    policyEngine.addPolicy(
      address(credentialRegistry),
      CredentialRegistry.removeCredential.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );
    policyEngine.addPolicy(
      address(credentialRegistry),
      CredentialRegistry.renewCredential.selector,
      address(identityAdminPolicy),
      new bytes32[](0)
    );

    // ----------------------------------------------------------------------
    // 3. Configure a simple KYC requirement through CredentialRegistryIdentityValidatorPolicy
    // ----------------------------------------------------------------------
    bytes32 CREDENTIAL_KYC = keccak256("common.KYC");
    bytes32[] memory requiredCredentials = new bytes32[](1);
    requiredCredentials[0] = CREDENTIAL_KYC;

    ICredentialRequirements.CredentialRequirementInput[] memory credentialRequirementInputs =
      new ICredentialRequirements.CredentialRequirementInput[](1);
    credentialRequirementInputs[0] =
      ICredentialRequirements.CredentialRequirementInput(keccak256("requirement.KYC"), requiredCredentials, 1, false);

    ICredentialRequirements.CredentialSourceInput[] memory credentialSourceInputs =
      new ICredentialRequirements.CredentialSourceInput[](1);
    credentialSourceInputs[0] = ICredentialRequirements.CredentialSourceInput(
      CREDENTIAL_KYC, address(identityRegistry), address(credentialRegistry), address(0)
    );

    CredentialRegistryIdentityValidatorPolicy identityValidatorPolicyImpl =
      new CredentialRegistryIdentityValidatorPolicy();
    bytes memory identityValidatorPolicyInitData = abi.encodeWithSelector(
      Policy.initialize.selector,
      address(policyEngine),
      deployer,
      abi.encode(credentialSourceInputs, credentialRequirementInputs)
    );
    ERC1967Proxy identityValidatorPolicyProxy =
      new ERC1967Proxy(address(identityValidatorPolicyImpl), identityValidatorPolicyInitData);
    CredentialRegistryIdentityValidatorPolicy identityValidatorPolicy =
      CredentialRegistryIdentityValidatorPolicy(address(identityValidatorPolicyProxy));

    // ----------------------------------------------------------------------
    // 4. Deploy the ERC20 implementation behind a proxy and bind ACE policies
    // ----------------------------------------------------------------------
    AceStandardERC20 tokenImplementation = new AceStandardERC20();
    bytes memory tokenInitData = abi.encodeWithSelector(
      AceStandardERC20.initialize.selector, tokenName, tokenSymbol, address(policyEngine), deployer
    );
    ERC1967Proxy tokenProxy = new ERC1967Proxy(address(tokenImplementation), tokenInitData);
    AceStandardERC20 token = AceStandardERC20(address(tokenProxy));

    // OnlyOwnerPolicy controlling mint/burn functions.
    OnlyOwnerPolicy tokenAdminPolicyImpl = new OnlyOwnerPolicy();
    bytes memory tokenAdminPolicyInitData =
      abi.encodeWithSelector(Policy.initialize.selector, address(policyEngine), deployer, new bytes(0));
    ERC1967Proxy tokenAdminPolicyProxy = new ERC1967Proxy(address(tokenAdminPolicyImpl), tokenAdminPolicyInitData);
    OnlyOwnerPolicy tokenAdminPolicy = OnlyOwnerPolicy(address(tokenAdminPolicyProxy));

    policyEngine.addPolicy(address(token), AceStandardERC20.mint.selector, address(tokenAdminPolicy), new bytes32[](0));
    policyEngine.addPolicy(address(token), AceStandardERC20.burn.selector, address(tokenAdminPolicy), new bytes32[](0));

    // Attach the ERC20 transfer extractor so ACE policies can access transfer arguments.
    ERC20TransferExtractor transferExtractor = new ERC20TransferExtractor();
    policyEngine.setExtractor(AceStandardERC20.transfer.selector, address(transferExtractor));
    policyEngine.setExtractor(AceStandardERC20.transferFrom.selector, address(transferExtractor));

    // Attach the identity validator to transfer functions using the extractor's PARAM_TO pointer.
    bytes32[] memory identityValidatorParams = new bytes32[](1);
    identityValidatorParams[0] = transferExtractor.PARAM_TO();
    policyEngine.addPolicy(
      address(token), AceStandardERC20.transfer.selector, address(identityValidatorPolicy), identityValidatorParams
    );
    policyEngine.addPolicy(
      address(token), AceStandardERC20.transferFrom.selector, address(identityValidatorPolicy), identityValidatorParams
    );

    vm.stopBroadcast();

    console.log("PolicyEngine:", address(policyEngine));
    console.log("IdentityRegistry:", address(identityRegistry));
    console.log("CredentialRegistry:", address(credentialRegistry));
    console.log("Identity Admin Policy:", address(identityAdminPolicy));
    console.log("Token Admin Policy:", address(tokenAdminPolicy));
    console.log("Identity Validator Policy:", address(identityValidatorPolicy));
    console.log("ERC20 Transfer Extractor:", address(transferExtractor));
    console.log("AceStandardERC20:", address(token));
  }
}
