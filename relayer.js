// relayer.js

require('dotenv').config();
const { JsonRpcProvider, Contract, id } = require('ethers');
const { ApiPromise, WsProvider, Keyring } = require('@polkadot/api');
const { hexToU8a, u8aToHex } = require('@polkadot/util');

async function main() {
  // 1) HTTP provider for Westend Asset-Hub EVM
  const evmProvider = new JsonRpcProvider(process.env.ASSET_HUB_RPC);

  // ABI to decode our stub event
  const vaultAbi = [
    "event CrossChainCollateralLockRequested(address indexed user, address token, uint256 amount, bytes32 destChain)"
  ];
  const vault = new Contract(process.env.VAULT_ADDRESS, vaultAbi, evmProvider);

  // Precompute topic hash
  const topic = id("CrossChainCollateralLockRequested(address,address,uint256,bytes32)");

  // 2) Connect via WebSocket to Paseo Asset Hub
  const wsProvider = new WsProvider(process.env.DEST_RPC);
  const api = await ApiPromise.create({ provider: wsProvider });
  
  // Log available modules to debug
  console.log("Available XCM modules:", 
    Object.keys(api.tx).filter(module => 
      module.toLowerCase().includes('xcm')
    )
  );

  // 3) Relayer account (must hold tokens on Paseo)
  const keyring = new Keyring({ type: 'sr25519' });
  const relayer = keyring.addFromUri(process.env.RELAYER_PRIVATE_KEY);

  console.log("🚀 Relayer running, polling for stub events...");

  // Track last processed block
  let lastBlock = await evmProvider.getBlockNumber();

  // 4) Poll every 10s
  setInterval(async () => {
    const currentBlock = await evmProvider.getBlockNumber();
    if (currentBlock <= lastBlock) return;

    const logs = await evmProvider.getLogs({
      address:   process.env.VAULT_ADDRESS,
      fromBlock: lastBlock + 1,
      toBlock:   currentBlock,
      topics:    [ topic ]
    });

    for (const log of logs) {
      const { args } = vault.interface.parseLog(log);
      const user      = args.user;
      const token     = args.token;
      const amount    = args.amount;
      const destChain = args.destChain;

      console.log(`🔔 StubEvent: ${amount} of ${token} locked by ${user}, dest=${destChain}`);

      // Properly convert Ethereum address to AccountId32 format
      const accountBytes = hexToU8a(user);
      const paddedAccount = new Uint8Array(32);
      paddedAccount.set(accountBytes, 32 - accountBytes.length);

      try {
        // Try with polkadotXcm module instead
        if (api.tx.polkadotXcm) {
          // Build V3 MultiLocation for destination parachain
          const dest = {
            V3: {
              parents: 1,
              interior: { X1: { Parachain: Number(process.env.DEST_PARA_ID) } }
            }
          };

          // Create XCM message using DepositAsset
          const message = {
            V3: [
              {
                WithdrawAsset: [{
                  id: { Concrete: { parents: 0, interior: 'Here' } },
                  fun: { Fungible: amount.toString() }
                }]
              },
              {
                DepositAsset: {
                  assets: { Wild: { All: null } },
                  beneficiary: {
                    parents: 0,
                    interior: { X1: { AccountId32: { network: null, id: paddedAccount } } }
                  }
                }
              }
            ]
          };

          const unsub = await api.tx.polkadotXcm
            .send(dest, message)
            .signAndSend(relayer, ({ status, dispatchError }) => {
              if (status.isInBlock) {
                console.log("✅ XCM sent in block", status.asInBlock.toHex());
                
                if (dispatchError) {
                  console.error("⚠️ Dispatch error:", dispatchError.toString());
                }
                
                unsub();
              }
            });
          
          console.log("🔄 Transaction submitted");
        } 
        // Fallback to xcmPallet if it exists
        else if (api.tx.xcmPallet) {
          // Build V2 MultiLocation for DEST_PARA_ID
          const dest = {
            V2: {
              parents: 1,
              interior: { X1: { Parachain: Number(process.env.DEST_PARA_ID) } }
            }
          };

          // Build beneficiary MultiLocation
          const beneficiary = {
            V2: {
              parents: 0,
              interior: {
                X1: { 
                  AccountId32: { 
                    network: 'Any', 
                    id: paddedAccount
                  } 
                }
              }
            }
          };

          // Build assets list
          const assets = {
            V2: [{
              id: { Concrete: { parents: 0, interior: 'Here' } },
              fun: { Fungible: amount.toString() }
            }]
          };

          const unsub = await api.tx.xcmPallet
            .reserveTransferAssets(dest, beneficiary, assets, 0)
            .signAndSend(relayer, ({ status }) => {
              if (status.isInBlock) {
                console.log("✅ XCM sent in block", status.asInBlock.toHex());
                unsub();
              }
            });
        }
        // Try with xTokens module as last resort
        else if (api.tx.xTokens) {
          console.log("Using xTokens module");
          
          // Destination for xTokens
          const dest = {
            V3: {
              parents: 1,
              interior: { X1: { Parachain: Number(process.env.DEST_PARA_ID) } }
            }
          };
          
          // Beneficiary as Accountid32
          const beneficiary = {
            V3: {
              parents: 0,
              interior: { X1: { AccountId32: { id: paddedAccount, network: null } } }
            }
          };
          
          const unsub = await api.tx.xTokens
            .transferMultiasset(
              { V3: { id: { Concrete: { parents: 0, interior: 'Here' } }, fun: { Fungible: amount.toString() } } },
              { V3: { parents: 1, interior: { X1: { Parachain: Number(process.env.DEST_PARA_ID) } } } },
              { V3: { parents: 0, interior: { X1: { AccountId32: { id: paddedAccount, network: null } } } } },
              'Unlimited'
            )
            .signAndSend(relayer, ({ status }) => {
              if (status.isInBlock) {
                console.log("✅ XCM sent in block", status.asInBlock.toHex());
                unsub();
              }
            });
        }
        else {
          throw new Error("No suitable XCM module found on the connected chain");
        }
      } catch (err) {
        console.error("❌ XCM send failed:", err);
      }
    }

    lastBlock = currentBlock;
  }, 10_000);
}

// Helper function to log dispatch errors
function logDispatchError(api, dispatchError) {
  let errorStr = "";
  
  if (dispatchError.isModule) {
    try {
      const decoded = api.registry.findMetaError(dispatchError.asModule);
      const { docs, name, section } = decoded;
      errorStr = `${section}.${name}: ${docs.join(' ')}`;
      console.error(`✖️ Error: ${errorStr}`);
    } catch (err) {
      errorStr = dispatchError.toString();
      console.error("✖️ Error decoding:", errorStr);
    }
  } else {
    errorStr = dispatchError.toString();
    console.error(`✖️ Error: ${errorStr}`);
  }
  
  return errorStr;
}

main().catch(console.error);