const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const networkName = hre.network.name;
  const chainId = hre.network.config.chainId || 31337;

  console.log(`🚀 Deploying CommitmentRegistry to ${networkName} (Chain ID: ${chainId})...`);

  const [deployer] = await hre.ethers.getSigners();
  console.log(`👤 Deployer Address: ${deployer.address}`);

  const balance = await hre.ethers.provider.getBalance(deployer.address);
  console.log(`💰 Deployer Balance: ${hre.ethers.formatEther(balance)} ETH`);

  const CommitmentRegistry = await hre.ethers.getContractFactory("CommitmentRegistry");
  const contract = await CommitmentRegistry.deploy();
  await contract.waitForDeployment();

  const address = await contract.getAddress();
  console.log(`✅ CommitmentRegistry deployed at: ${address}`);

  const artifact = await hre.artifacts.readArtifact("CommitmentRegistry");

  const deployInfo = {
    contractAddress: address,
    chainId: chainId,
    network: networkName,
    deployer: deployer.address,
    deployedAt: new Date().toISOString(),
    abi: artifact.abi
  };

  const outputPath = path.join(__dirname, "../deployed.json");
  fs.writeFileSync(outputPath, JSON.stringify(deployInfo, null, 2));
  console.log(`📄 Saved deployment manifest to ${outputPath}`);

  if (networkName !== "hardhat" && networkName !== "localhost") {
    console.log("\n🔍 Verification command:");
    console.log(`npx hardhat verify --network ${networkName} ${address}`);
  }
}

main().catch((err) => {
  console.error("❌ Deploy failed:", err);
  process.exit(1);
});
