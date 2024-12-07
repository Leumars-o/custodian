# Custodian: Stacks NFT Escrow Contract

## Overview

Custodian is a sophisticated NFT escrow contract built for the Stacks blockchain, designed to facilitate secure and trustless NFT trades with advanced tracking and event logging capabilities.

## Key Features

- **Secure NFT Transfers**: Intermediated, safe NFT trading mechanism
- **Receipt Verification**: Explicit NFT receipt tracking
- **Escrow Timeout**: Built-in refund option
- **Chainhook Integration**: Real-time event logging and external tracking
- **Comprehensive Error Handling**: Detailed error codes for various scenarios

## Contract Architecture

### Core Components

- **NFT Trait Interface**: Standardized NFT transfer protocol
- **Error Codes**: Predefined constants for different failure scenarios
- **Mappings**:
  - `nft-receipts`: Tracks NFT receipt status
  - `escrow-transactions`: Stores escrow transaction details

## Chainhook Integration Highlights

### Event Logging

The contract leverages Chainhook-friendly event logging through strategic `print` function calls, enabling rich, real-time tracking of NFT escrow processes.

#### Supported Event Types

1. **NFT Escrow Creation**
   ```clarity
   (print {
     notification: "nft-escrow-created",
     payload: {
       nft-contract: (contract-of nft-contract),
       nft-id: nft-id,
       seller: tx-sender,
       buyer: buyer,
       price: sale-price
     }
   })
   ```

2. **NFT Receipt Confirmation**
   ```clarity
   (print {
     notification: "nft-receipt-confirmed",
     payload: {
       nft-contract: nft-contract,
       nft-id: nft-id,
       seller: tx-sender
     }
   })
   ```

3. **NFT Transfer Completion**
   ```clarity
   (print {
     notification: "nft-transfer-completed",
     payload: {
       nft-contract: (contract-of nft-contract),
       nft-id: nft-id,
       buyer: (get buyer escrow-details)
     }
   })
   ```

4. **NFT Escrow Refund**
   ```clarity
   (print {
     notification: "nft-escrow-refunded",
     payload: {
       nft-contract: (contract-of nft-contract),
       nft-id: nft-id,
       seller: (get seller escrow-details)
     }
   })
   ```

### Chainhook Use Cases

- Real-time event tracking
- External system notifications
- Marketplace analytics
- Automated trading systems
- Compliance and auditing

## Main Contract Functions

1. **`create-nft-escrow`**
   - Initiates escrow transaction
   - Validates buyer, NFT contract, and sale price
   - Transfers NFT to escrow contract

2. **`confirm-nft-receipt`**
   - Seller confirms NFT receipt
   - Logs receipt in contract
   - Triggers Chainhook event

3. **`complete-nft-transfer`**
   - Finalizes NFT transfer to buyer
   - Verifies receipt and escrow status
   - Transfers NFT to buyer

4. **`refund-nft`**
   - Refunds NFT to seller if escrow expires
   - Prevents asset lockup


## Escrow Process

1. Seller initiates escrow
2. NFT transferred to contract
3. Seller confirms receipt
4. Buyer completes transfer
5. Refund possible after timeout

## Usage Example

```clarity
;; Create an escrow
(create-nft-escrow 
  nft-contract-principal 
  nft-id 
  buyer-principal 
  sale-price
)

;; Confirm receipt
(confirm-nft-receipt 
  nft-contract-principal 
  nft-id
)

;; Complete transfer
(complete-nft-transfer 
  nft-contract-principal 
  nft-id
)
```

## Utility Functions

- `get-escrow-status`: Retrieve escrow details
- `get-nft-receipt-status`: Check receipt status
- `is-valid-nft-contract`: Validate NFT contract


## Additional Resources

- [Stacks Blockchain Documentation](https://docs.stacks.co)
- [Chainhooks Overview](https://docs.stacks.co/build-apps/references/chainhooks)