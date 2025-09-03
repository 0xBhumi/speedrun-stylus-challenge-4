"use client";

import React, { useEffect, useState } from "react";
import { IMultiSig } from "./IMultiSig";
import { ethers } from "ethers";

export default function DebugContracts() {
  const [contract, setContract] = useState<ethers.Contract | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [numConfirmations, setNumConfirmations] = useState<number>(0);
  const [transactionCount, setTransactionCount] = useState<number>(0);
  const [loading, setLoading] = useState<boolean>(false);
  const [lastTxHash, setLastTxHash] = useState<string | null>(null);
  const [lastSubmittedTxIndex, setLastSubmittedTxIndex] = useState<number | null>(null);
  const [signerAddress, setSignerAddress] = useState<string | null>(null);
  const [formData, setFormData] = useState({
    to: "",
    value: "",
    data: "",
    txIndex: "",
    checkAddress: "",
    owners: "", // Add this field for comma-separated owner addresses
    numConfirmationsRequired: "", // Add this field for required confirmations
  });
  const [isOwnerResult, setIsOwnerResult] = useState<boolean | null>(null);

  useEffect(() => {
    initializeContract();
  }, []);

  const initializeContract = async () => {
    try {
      if (typeof window === "undefined") return;

      const contractAddress="0x8f5a580641a66d97cffc68b846eaca5b8766af9a";
      const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL || '';
      const privateKey = process.env.NEXT_PUBLIC_PRIVATE_KEY || '';
      // const contractAddress = process.env.NEXT_PUBLIC_CONTRACT_ADDRESS;
      // const rpcUrl = process.env.NEXT_PUBLIC_RPC_URL;
      // const privateKey = process.env.NEXT_PUBLIC_PRIVATE_KEY;

      if (!contractAddress || !rpcUrl || !privateKey) {
        throw new Error("Missing environment variables. Please check your .env.local file");
      }

      const provider = new ethers.JsonRpcProvider(rpcUrl);

      try {
        const network = await provider.getNetwork();
        console.log("Connected to network:", network.name);
      } catch (e) {
        throw new Error("Failed to connect to network. Please ensure the Nitro dev node is running on localhost:8547", { cause: e });
      }

      const signer = new ethers.Wallet(privateKey, provider);
      const address = await signer.getAddress();
      setSignerAddress(address);
      console.log("Signer address:", address);

      const newContract = new ethers.Contract(contractAddress, IMultiSig, signer);

      // Verify contract deployment
      const code = await provider.getCode(contractAddress);
      if (code === "0x") {
        throw new Error("No contract deployed at the specified address. Please deploy the contract first.");
      }

      setContract(newContract);

      // Test basic contract interaction
      try {
        await newContract.numConfirmationsRequired();
        console.log("Contract connection successful");
      } catch (e) {
        throw new Error("Contract interaction failed. Please verify the contract ABI and address", { cause: e });
      }
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Failed to initialize contract. Please check if the Nitro dev node is running.";
      setError(errorMessage);
      console.error("Contract initialization error:", err);
    }
  };

  // Helper to create a test transaction to the signer's address
  const createTestTransaction = async () => {
    if (!contract || !signerAddress) return;
    
    setLoading(true);
    setError(null);
    
    try {
      // Create a transaction sending a small amount back to the signer
      const tx = await contract.submitTransaction(
        signerAddress,  // Send to our own address (guaranteed to accept ETH)
        ethers.parseEther("0.01"), // 0.01 ETH (small amount)
        "0x", // No data
        { gasLimit: 1000000 }
      );
      
      console.log("Test transaction submitted:", tx.hash);
      setLastTxHash(tx.hash);
      
      const receipt = await tx.wait();
      console.log("Test transaction confirmed:", receipt);
      
      // Get the transaction index
      const txCount = await contract.getTransactionCount();
      const newTxIndex = Number(txCount) - 1;
      setLastSubmittedTxIndex(newTxIndex);
      
      // Automatically confirm the transaction too
      const confirmTx = await contract.confirmTransaction(newTxIndex, { gasLimit: 1000000 });
      await confirmTx.wait();
      console.log("Test transaction confirmed by signer");
      
      setFormData({
        ...formData,
        txIndex: newTxIndex.toString()
      });
      
      await fetchContractData();
    } catch (err: any) {
      console.error("Failed to create test transaction:", err);
      setError(err.message || "Failed to create test transaction");
    } finally {
      setLoading(false);
    }
  };

  const fetchContractData = async () => {
    if (!contract) return;

    try {
      setLoading(true);
      const [numRequired, txCount] = await Promise.all([
        contract.numConfirmationsRequired(),
        contract.getTransactionCount(),
      ]);

      setNumConfirmations(Number(numRequired));
      setTransactionCount(Number(txCount));

      console.log("Contract state updated:", {
        numConfirmations: Number(numRequired),
        transactionCount: Number(txCount),
      });
    } catch (error) {
      console.error("Error fetching contract data:", error);
      setError("Failed to fetch contract data. Please check console for details.");
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (contract) {
      fetchContractData();
    }
  }, [contract]);

  const handleSubmit = async (e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    if (!contract) {
      setError("Contract not initialized. Please wait for the contract to load.");
      return;
    }

    setError(null);
    setLoading(true);
    setLastTxHash(null);

    const form = e.currentTarget;
    const action = form.getAttribute("data-action");

    try {
      let tx;
      switch (action) {
        case "deposit":
          if (!formData.value || parseFloat(formData.value) <= 0) {
            throw new Error("Please enter a valid amount greater than 0 ETH.");
          }
          tx = await contract.deposit({
            value: ethers.parseEther(formData.value),
          });
          break;

        case "submitTransaction":
          if (!ethers.isAddress(formData.to)) {
            throw new Error("Invalid recipient address. Please check the address format.");
          }
          if (!formData.value || parseFloat(formData.value) < 0) {
            throw new Error("Please enter a valid amount of ETH.");
          }
          
          console.log("Submitting transaction to:", formData.to);
          console.log("Value:", formData.value, "ETH");
          
          tx = await contract.submitTransaction(formData.to, ethers.parseEther(formData.value), formData.data || "0x");
          // Set the transaction index after submission
          const txCount = await contract.getTransactionCount();
          setLastSubmittedTxIndex(Number(txCount) - 1);
          break;

        case "confirmTransaction":
          tx = await contract.confirmTransaction(formData.txIndex);
          console.log(contract.interface);
          const txDetails = await contract.getTransaction(parseInt(formData.txIndex));
          console.log("Transaction details after confirmation:", txDetails);
          break;

        case "executeTransaction":
          if (!formData.txIndex || parseInt(formData.txIndex) < 0) {
            throw new Error("Please enter a valid transaction index.");
          }
          
          try {
            // First check transaction status
            const txDetails = await contract.getTransaction(parseInt(formData.txIndex));
            const requiredConfirmations = await contract.numConfirmationsRequired();
            const txIndex = parseInt(formData.txIndex);
            
            const toAddress = txDetails[0];
            const txValue = txDetails[1];
            const txData = txDetails[2];
            const isExecuted = txDetails[3];
            const currentConfirmations = txDetails[4];
            
            console.log("--- TRANSACTION DETAILS ---");
            console.log("To address:", toAddress);
            console.log("Value:", ethers.formatEther(txValue), "ETH");
            console.log("Data:", txData);
            console.log("Is executed:", isExecuted);
            console.log("Current confirmations:", currentConfirmations);
            console.log("Required confirmations:", requiredConfirmations);
            console.log("--------------------------");
            
            if (isExecuted) {
              throw new Error("Transaction has already been executed.");
            }
            // Try with a gas limit override to avoid estimation errors
            tx = await contract.executeTransaction(txIndex, {
              gasLimit: 5000000
            });
            
          } catch (err: any) {
            console.log("Error data:", err);
            
            if (err.data === "0xd6bed873") {
              // Try to confirm the transaction first, then execute
              try {
                console.log("Attempting to confirm transaction first...");
                await contract.confirmTransaction(parseInt(formData.txIndex), {
                  gasLimit: 1000000
                });
                console.log("Confirmation successful, now executing...");
                tx = await contract.executeTransaction(parseInt(formData.txIndex), {
                  gasLimit: 5000000
                });
              } catch (confirmErr) {
                console.log("Error during confirmation attempt:", confirmErr);
                throw new Error("Transaction doesn't have enough confirmations to execute. Please ensure all required owners have confirmed the transaction.");
              }
            } else {
              // More helpful error message for transaction execution failures
              const errorMessage = err.reason || 
                "Transaction execution failed. This could be because the recipient can't accept ETH, " +
                "or there's not enough balance in the multisig contract. " +
                "Try sending to an EOA (regular wallet) instead of a contract.";
              throw new Error(errorMessage);
            }
          }
          break;

        case "revokeConfirmation":
          if (!formData.txIndex || parseInt(formData.txIndex) < 0) {
            throw new Error("Please enter a valid transaction index.");
          }
          tx = await contract.revokeConfirmation(parseInt(formData.txIndex));
          break;

        case "checkOwner":
          if (!ethers.isAddress(formData.checkAddress)) {
            throw new Error("Invalid address. Please check the address format.");
          }
          const isOwner = await contract.isOwner(formData.checkAddress);
          setIsOwnerResult(isOwner);
          console.log("Owner check result:", isOwner);
          break;

        case "initialize":
          const ownerAddresses = formData.owners.split(",").map(addr => addr.trim());
          if (ownerAddresses.length === 0 || ownerAddresses.some(addr => !ethers.isAddress(addr))) {
            throw new Error("Please provide valid owner addresses separated by commas.");
          }
          if (
            !formData.numConfirmationsRequired ||
            parseInt(formData.numConfirmationsRequired) <= 0 ||
            parseInt(formData.numConfirmationsRequired) > ownerAddresses.length
          ) {
            throw new Error(`Number of required confirmations must be between 1 and ${ownerAddresses.length}.`);
          }
          tx = await contract.initialize(ownerAddresses, ethers.toNumber(formData.numConfirmationsRequired), {
            gasLimit: 10000000,
          });
          break;

        default:
          throw new Error("Invalid action. Please check the form settings.");
      }

      if (tx) {
        console.log("Transaction submitted:", tx.hash);
        setLastTxHash(tx.hash);

        const receipt = await tx.wait();
        console.log("Transaction confirmed:", receipt);

        if (action !== "checkOwner") {
          setFormData({
            to: "",
            value: "",
            data: "",
            txIndex: "",
            checkAddress: "",
            owners: "",
            numConfirmationsRequired: "",
          });
        }
      }

      await fetchContractData();
    } catch (err: any) {
      console.error("Transaction error:", err);
      let errorMessage = "Transaction failed. Please check the console for details.";

      if (err instanceof Error) {
        const ethersError = err as any;
        const reason = ethersError.reason;
        const customErrorData = ethersError.data;

        if (reason) {
          errorMessage = reason;
        } else if (customErrorData) {
          errorMessage = `Execution reverted with custom error data: ${customErrorData}. `;
          if (customErrorData === "0xd6bed873") {
            errorMessage += "(This means: ConfirmationNumberNotEnough)";
          }
        } else {
          errorMessage = err.message;
        }
      }
      setError(errorMessage);
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setFormData({
      ...formData,
      [e.target.name]: e.target.value,
    });
  };

  return (
    <div className="flex flex-col gap-6 w-full max-w-4xl mx-auto p-6">
      <h1 className="text-3xl font-bold text-center">Multi-Signature Wallet</h1>
      <p className="text-center text-lg">Use this interface to interact with your multi-signature wallet smart contract. Follow the steps below to manage funds securely.</p>

      {error && (
        <div className="alert alert-error overflow-x-auto max-h-24">
          <span className="font-bold">Error:</span>
          <span className="">{error}</span>
        </div>
      )}

      {loading && (
        <div className="alert alert-info">
          <span>Processing transaction... Please wait.</span>
        </div>
      )}

      {lastTxHash && (
        <div className="alert alert-success overflow-x-auto">
          <span>Transaction successful: <a href={`http://localhost:3000/blockexplorer/transaction/${lastTxHash}`} target="_blank" rel="noopener noreferrer" className="link link-primary">{lastTxHash}</a></span>
        </div>
      )}

      {lastSubmittedTxIndex !== null && (
        <div className="alert alert-info">
          <span>Last submitted transaction index: {lastSubmittedTxIndex}. Use this index to confirm or execute the transaction in the 'Manage Transactions' section below.</span>
        </div>
      )}

      {/* Contract Status */}
      <div className="card bg-base-200 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">Contract Status</h2>
          <div className="space-y-2">
            <p><strong>Required Confirmations:</strong> {numConfirmations}</p>
            <p><strong>Total Transactions:</strong> {transactionCount}</p>
          </div>
        </div>
      </div>

      {/* Initialize Contract */}
      <div className="card bg-base-200 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">1. Initialize Contract</h2>
          <p className="mb-4">Set up the multi-signature wallet by defining owner addresses and the number of confirmations required for transactions. This step is crucial for security.</p>
          <form data-action="initialize" onSubmit={handleSubmit} className="space-y-4">
            <div className="form-control">
              <label className="label"><span className="label-text">Owner Addresses (comma-separated)</span></label>
              <input
                type="text"
                name="owners"
                value={formData.owners}
                onChange={handleInputChange}
                placeholder="0x123..., 0x456..."
                className="input input-bordered w-full"
                required
              />
              <label className="label"><span className="label-text-alt">Enter multiple addresses separated by commas.</span></label>
            </div>
            <div className="form-control">
              <label className="label"><span className="label-text">Required Confirmations</span></label>
              <input
                type="number"
                name="numConfirmationsRequired"
                value={formData.numConfirmationsRequired}
                onChange={handleInputChange}
                placeholder="2"
                className="input input-bordered w-full"
                required
                min="1"
              />
              <label className="label"><span className="label-text-alt">Must be between 1 and the number of owners.</span></label>
            </div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              Initialize Contract
            </button>
          </form>
        </div>
      </div>

      {/* Deposit ETH */}
      <div className="card bg-base-200 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">2. Deposit ETH</h2>
          <p className="mb-4">Deposit Ether into the contract to enable transactions. Ensure there are sufficient funds for operations. The ETH will be deposited to the multi-signature wallet contract at address: <span className="font-mono">0xa6e41ffd769491a42a6e5ce453259b93983a22ef</span>.</p>
          <form onSubmit={handleSubmit} data-action="deposit" className="space-y-4">
            <div className="form-control">
              <label className="label"><span className="label-text">Amount (ETH)</span></label>
              <input
                type="text"
                name="value"
                value={formData.value}
                onChange={handleInputChange}
                className="input input-bordered w-full"
                placeholder="0.1"
                required
              />
              <label className="label"><span className="label-text-alt">Enter the amount of ETH to deposit.</span></label>
            </div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              Deposit ETH
            </button>
          </form>
        </div>
      </div>

      {/* Submit Transaction */}
      <div className="card bg-base-200 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">3. Submit Transaction</h2>
          <p className="mb-4">Propose a new transaction by specifying the recipient, amount, and optional data. This transaction will need confirmations before execution.</p>
          <form onSubmit={handleSubmit} data-action="submitTransaction" className="space-y-4">
            <div className="form-control">
              <label className="label"><span className="label-text">To Address</span></label>
              <input
                type="text"
                name="to"
                value={formData.to}
                onChange={handleInputChange}
                className="input input-bordered w-full"
                placeholder="0x..."
                required
              />
              <label className="label"><span className="label-text-alt">Enter the recipient's Ethereum address.</span></label>
            </div>
            <div className="form-control">
              <label className="label"><span className="label-text">Value (ETH)</span></label>
              <input
                type="text"
                name="value"
                value={formData.value}
                onChange={handleInputChange}
                className="input input-bordered w-full"
                placeholder="0.1"
                required
              />
              <label className="label"><span className="label-text-alt">Enter the amount of ETH to send.</span></label>
            </div>
            <div className="form-control">
              <label className="label"><span className="label-text">Data (hex)</span></label>
              <input
                type="text"
                name="data"
                value={formData.data}
                onChange={handleInputChange}
                className="input input-bordered w-full"
                placeholder="0x"
              />
              <label className="label"><span className="label-text-alt">Optional: Enter hex data for smart contract calls.</span></label>
            </div>
            <div className="flex justify-between">
              <button type="submit" className="btn btn-primary" disabled={loading}>
                Submit Transaction
              </button>
              <button type="button" onClick={createTestTransaction} className="btn btn-secondary" disabled={loading}>
                Create Test Transaction
              </button>
            </div>
            {loading && <p className="text-sm">Creating transaction...</p>}
            <p className="text-sm bg-info bg-opacity-20 p-2 rounded">
              <strong>Tip:</strong> If you're having trouble executing transactions, try the "Create Test Transaction" button. 
              This will create a simple transaction that sends a small amount of ETH back to your own address (which is guaranteed to work).
            </p>
          </form>
        </div>
      </div>

      {/* Transaction Management */}
      <div className="card bg-base-200 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">4. Manage Transactions</h2>
          <p className="mb-4">Approve (confirm) pending transactions or execute transactions that have met the required number of confirmations. Owners can also revoke their prior confirmations.</p>
          <div className="space-y-6">
            <form onSubmit={handleSubmit} data-action="confirmTransaction" className="space-y-4">
              <div className="form-control">
                <label className="label"><span className="label-text">Confirm Transaction (Approve)</span></label>
                <input
                  type="number"
                  name="txIndex"
                  value={formData.txIndex}
                  onChange={handleInputChange}
                  className="input input-bordered w-full"
                  placeholder="Transaction Index"
                  required
                />
                <label className="label"><span className="label-text-alt">Enter the index of the transaction to approve. This records your signature but does not execute the transaction.</span></label>
              </div>
              <button type="submit" className="btn btn-success" disabled={loading}>
                Confirm (Approve)
              </button>
            </form>

            <form onSubmit={handleSubmit} data-action="executeTransaction" className="space-y-4">
              <div className="form-control">
                <label className="label"><span className="label-text">Execute Transaction</span></label>
                <input
                  type="number"
                  name="txIndex"
                  value={formData.txIndex}
                  onChange={handleInputChange}
                  className="input input-bordered w-full"
                  placeholder="Transaction Index"
                  required
                />
                <label className="label"><span className="label-text-alt">Execute a transaction once it has the required number of confirmations. This will perform the actual transfer or contract call.</span></label>
              </div>
              <button type="submit" className="btn btn-accent" disabled={loading}>
                Execute
              </button>
            </form>

            <form onSubmit={handleSubmit} data-action="revokeConfirmation" className="space-y-4">
              <div className="form-control">
                <label className="label"><span className="label-text">Revoke Confirmation</span></label>
                <input
                  type="number"
                  name="txIndex"
                  value={formData.txIndex}
                  onChange={handleInputChange}
                  className="input input-bordered w-full"
                  placeholder="Transaction Index"
                  required
                />
                <label className="label"><span className="label-text-alt">Revoke your prior approval for a transaction if needed.</span></label>
              </div>
              <button type="submit" className="btn btn-error" disabled={loading}>
                Revoke
              </button>
            </form>
          </div>
        </div>
      </div>

      {/* Check Owner Status */}
      <div className="card bg-base-200 shadow-xl">
        <div className="card-body">
          <h2 className="card-title">5. Check Owner Status</h2>
          <p className="mb-4">Verify if an address is an owner of this multi-signature wallet.</p>
          <form onSubmit={handleSubmit} data-action="checkOwner" className="space-y-4">
            <div className="form-control">
              <label className="label"><span className="label-text">Address</span></label>
              <input
                type="text"
                name="checkAddress"
                value={formData.checkAddress}
                onChange={handleInputChange}
                className="input input-bordered w-full"
                placeholder="0x..."
                required
              />
              <label className="label"><span className="label-text-alt">Enter the address to check.</span></label>
            </div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              Check Owner
            </button>
            {isOwnerResult !== null && (
              <div className={`alert ${isOwnerResult ? "alert-success" : "alert-error"}`}>
                <span>Address is {isOwnerResult ? "an owner" : "not an owner"} of this wallet.</span>
              </div>
            )}
          </form>
        </div>
      </div>
    </div>
  );
}