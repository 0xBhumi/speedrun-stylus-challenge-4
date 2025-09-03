import { ethers } from "ethers";
import { performance } from "perf_hooks";

const STYLUS_CONTRACT_ADDRESS = "0xa6e41ffd769491a42a6e5ce453259b93983a22ef";
const RPC_URL = "http://localhost:8547"; // typical for Nitro devnet
const PRIVATE_KEY = "0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659";

const provider = new ethers.JsonRpcProvider(RPC_URL);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

// ArbWasm precompile for program init gas measurements
const arbWasmAddress = "0x0000000000000000000000000000000000000071";
const arbWasmAbi = ["function programInitGas(address) view returns (uint64, uint64)"];

// ArbWasmCache precompile for cache management
const arbWasmCacheAbi = [
  "function evictCodehash(bytes32) external",
  "function cacheProgram(address) external",
  "function codehashIsCached(bytes32) view returns (bool)",
];

async function getCodehash(addr) {
  const bytecode = await provider.getCode(addr);
  return ethers.keccak256(bytecode);
}

async function main() {
  const arbWasm = new ethers.Contract(arbWasmAddress, arbWasmAbi, provider);
  const cache = new ethers.Contract("0x0000000000000000000000000000000000000072", arbWasmCacheAbi, signer);
  const codehash = await getCodehash(STYLUS_CONTRACT_ADDRESS);

  console.log("📋 Program Init Gas Analysis");
  console.log("=".repeat(50));
  console.log(`📍 Contract: ${STYLUS_CONTRACT_ADDRESS}`);
  console.log(`🔑 Codehash: ${codehash}`);
  console.log("");

  // Ensure program is evicted (cold state)
  console.log(`🧊 Evicting contract from cache...`);
  try {
    await (await cache.evictCodehash(codehash)).wait();
    console.log("✅ Contract evicted successfully");
  } catch (error) {
    console.log("⚠️ Eviction failed (may already be evicted):", error.message);
  }

  // Measure cold call (without cache)
  console.log(`\n❄️ COLD CALL (Without Cache)`);
  console.log("⏱️ Measuring program init gas and latency...");
  let start = performance.now();
  const [coldInitGas, coldCachedGas] = await arbWasm.programInitGas(STYLUS_CONTRACT_ADDRESS);
  let end = performance.now();
  const coldLatency = end - start;

  console.log(`💰 Program Init Gas (Cold): ${coldInitGas.toString()}`);
  console.log(`⚡ Program Init Gas (If Cached): ${coldCachedGas.toString()}`);
  console.log(`⏰ Latency: ${coldLatency.toFixed(2)} ms`);

  // Cache the program
  console.log(`\n🔥 Caching program...`);
  try {
    await (await cache.cacheProgram(STYLUS_CONTRACT_ADDRESS)).wait();
    console.log("✅ Program cached successfully");
  } catch (error) {
    console.log("⚠️ Caching failed:", error.message);
  }

  // Measure warm call (with cache)
  console.log(`\n♨️ WARM CALL (With Cache)`);
  console.log("⏱️ Measuring program init gas and latency...");
  start = performance.now();
  const [warmInitGas, warmCachedGas] = await arbWasm.programInitGas(STYLUS_CONTRACT_ADDRESS);
  end = performance.now();
  const warmLatency = end - start;

  console.log(`💰 Program Init Gas (Warm): ${warmInitGas.toString()}`);
  console.log(`⚡ Program Init Gas (If Cached): ${warmCachedGas.toString()}`);
  console.log(`⏰ Latency: ${warmLatency.toFixed(2)} ms`);

  // Analysis
  console.log(`\n📊 ANALYSIS`);
  console.log("=".repeat(50));
  const gasDifference = BigInt(warmInitGas.toString()) - BigInt(warmCachedGas.toString());
  const latencyDifference = coldLatency - warmLatency;
  const latencyImprovement = (latencyDifference / coldLatency) * 100;

  console.log(`💾 Gas Difference (Cold - Warm): ${gasDifference.toString()}`);
  console.log(`⚡ Latency Difference: ${latencyDifference.toFixed(2)} ms`);
  console.log("=".repeat(50));
  console.log(`\n`);
  console.log(`📈 Latency Improvement: ${latencyImprovement.toFixed(2)}%`);
  console.log(`💾 Gas Savings: ${gasDifference.toString()}`);
  console.log(`\n`);
  console.log("=".repeat(50));

  if (gasDifference > 0n) {
    console.log(`🎯 Cache provides ${gasDifference.toString()} gas savings!`);
  } else if (gasDifference === 0n) {
    console.log(`📝 No gas difference observed between cold and warm calls`);
  } else {
    console.log(`🤔 Warm call uses more gas than cold call (unexpected)`);
  }
}

main().catch(console.error);
