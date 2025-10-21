# Intégrer Chainlink ACE à un ERC-20 standard

Ce guide décrit, étape par étape, comment transformer un ERC-20 classique en jeton compatible Chainlink ACE. Il s'appuie sur le script [`script/DeployAceStandardERC20.s.sol`](../script/DeployAceStandardERC20.s.sol) qui orchestre le déploiement complet (Policy Engine, CCID, politiques et token).

## Pré-requis

- **Foundry** installé et configuré (`forge`, `cast`).
- Un compte EOA disposant de fonds sur le réseau ciblé et sa clé privée disponible sous forme hexadécimale.
- Accès à un endpoint RPC pour le réseau de déploiement.
- Variables d'environnement configurées pour le script :
  - `PRIVATE_KEY` – clé privée du déployeur.
  - `RPC_URL` – URL RPC utilisée par Foundry (`forge script` lit automatiquement `ETH_RPC_URL`).
  - Optionnel : `TOKEN_NAME` / `TOKEN_SYMBOL` pour personnaliser le jeton.

## Vue d'ensemble des composants

| Étape | Contrat / composant | Rôle |
|-------|---------------------|------|
| 1 | `PolicyEngine` | Cerveau d'ACE. Évalue les politiques pour chaque appel « protégé ». |
| 2 | `IdentityRegistry` & `CredentialRegistry` | Stockent les identités (CCID) et leurs credentials. |
| 3 | `CredentialRegistryIdentityValidatorPolicy` | Politique qui vérifie qu'un destinataire possède un credential valide. |
| 4 | `AceStandardERC20` | ERC-20 standard dont les fonctions critiques appellent `runPolicy`. |
| 4 bis | `OnlyOwnerPolicy` | Politique générique qui restreint les actions d'administration au déployeur. |
| 4 ter | `ERC20TransferExtractor` | Expose les arguments `from/to/amount` aux politiques.

## Étape 1 : déployer le Policy Engine

1. Déployer l'implémentation de `PolicyEngine`.
2. Déployer un proxy `ERC1967Proxy` pointant vers cette implémentation.
3. Initialiser le proxy avec `PolicyEngine.initialize(IPolicyEngine.PolicyResult.Allowed)` pour accepter les appels par défaut tant qu'aucune politique ne les rejette.

Dans le script, cela correspond aux lignes qui instancient `PolicyEngine policyEngineImplementation`, encodent `policyEngineInitData`, puis créent `policyEngineProxy`.

## Étape 2 : préparer l'infrastructure CCID

1. **IdentityRegistry** – mappe une adresse vers un identifiant cross-chain.
2. **CredentialRegistry** – stocke les credentials liés à un CCID.
3. Chaque registre est déployé via un proxy et initialisé avec l'adresse du `PolicyEngine` pour déléguer la gouvernance à ACE.
4. On attache ensuite une `OnlyOwnerPolicy` aux méthodes d'administration (`registerIdentity`, `registerCredential`, etc.) afin que seul le déployeur puisse gérer les identités et credentials au départ.

Le script crée deux instances `OnlyOwnerPolicy` (une pour les registres, une pour le token) et utilise `policyEngine.addPolicy` pour lier ces politiques aux sélecteurs concernés.

## Étape 3 : définir la règle KYC

1. On choisit un identifiant de credential (`common.KYC`).
2. On décrit l'exigence via `CredentialRequirementInput` (au moins 1 credential KYC valide, non global).
3. On indique où récupérer les credentials via `CredentialSourceInput` (les registres déployés).
4. On déploie `CredentialRegistryIdentityValidatorPolicy` en lui passant ces données encodées.

La politique est ensuite ajoutée au `PolicyEngine` avec un paramètre supplémentaire (provenant de `ERC20TransferExtractor.PARAM_TO()`) pour préciser quel champ de l'appel doit être validé.

## Étape 4 : déployer un ERC-20 standard compatible ACE

1. Le contrat [`AceStandardERC20`](../packages/tokens/erc-20/src/AceStandardERC20.sol) étend `ERC20Upgradeable` et `PolicyProtected`.
2. Les méthodes critiques (`transfer`, `transferFrom`, `approve`, `mint`, `burn`) utilisent les modificateurs `runPolicy` afin que le `PolicyEngine` puisse exécuter les contrôles attachés à ces sélecteurs.
3. `supportsInterface` est surchargé pour déléguer à `PolicyProtected` et conserver la compatibilité ERC-165.
4. Le script déploie le contrat derrière un `ERC1967Proxy` et l'initialise avec le Policy Engine et le propriétaire initial.
5. Une seconde `OnlyOwnerPolicy` verrouille `mint`/`burn` pour éviter les abus.
6. Enfin, le script enregistre l'extracteur `ERC20TransferExtractor` et rattache la politique KYC aux fonctions `transfer` et `transferFrom`.

## Exécution du script

Lancer le script Foundry :

```bash
forge script script/DeployAceStandardERC20.s.sol \
  --broadcast \
  --rpc-url "$ETH_RPC_URL"
```

> 💡 Assurez-vous que `ETH_RPC_URL` pointe vers le bon réseau et que le compte dispose de fonds.

Le script affichera en console les adresses de tous les contrats déployés pour les renseigner ensuite dans vos outils (dApp, backend, etc.).

## Allonger la logique métier

- **Autres policies** : vous pouvez ajouter des politiques supplémentaires (listes de sanctions, seuils de montants, etc.) en répétant les appels à `policyEngine.addPolicy`.
- **Rôles multiples** : remplacez `OnlyOwnerPolicy` par `OnlyAuthorizedSenderPolicy` ou une politique personnalisée pour déléguer des rôles spécifiques.
- **Contextes personnalisés** : en exposant des extracteurs supplémentaires ou en utilisant `runPolicyWithContext`, vous pouvez transmettre des données applicatives (ex : signature off-chain).

## Nettoyage et opérations

- **Enregistrement des identités** : depuis le compte autorisé, appelez `IdentityRegistry.registerIdentity` pour l'adresse cible.
- **Ajout de credentials** : appelez `CredentialRegistry.registerCredential` avec le CCID et l'ID de credential.
- **Renouvellement / retrait** : utilisez les autres méthodes du registre, protégées par la même politique d'administration.

Vous disposez désormais d'un ERC-20 standard où chaque transfert est validé par Chainlink ACE en fonction des credentials CCID enregistrés.

### 