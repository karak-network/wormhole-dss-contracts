# Wormhole DSS

## Setup to Enable Wormhole DSS validation for NTT

_Note: Currently Wormhole DSS is only supported on EVM chains that already have a deployment of Karak Protocol on them._

To setup the Native Token Transfer (NTT) protocol you can follow this [guide](https://wormhole.com/docs/build/contract-integrations/native-token-transfers/deployment-process/deploy-to-evm/). After that to enable Wormhole DSS validation to NTT you can follow the following steps:

Add the following environment variables to the `.env` file:

```
WORMHOLE_DSS=<WORMHOLE_DSS_ADDRESS_ON_THAT_CHAIN>
NTT_MANAGER=<NTT_MANAGER_ADDRESS_ON_THAT_CHAIN>
```

and run the following command to deploy the contracts:

```
forge script script/deployDSS.s.sol:DeployDSS --rpc-url <RPC_URL_OF_THAT_CHAIN> --broadcast --verify --etherscan-api-key <ETHERSCAN_API_KEY_OF_THAT_CHAIN>
```

This will update your NTT setup to also add the Wormhole DSS validation.