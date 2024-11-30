
;; title: custodian
;; summary: A Stacks NFT Escrow Contract
;; description: Custodian is a Stacks NFT Escrow Contract that allows users to securely trade NFTs on the Stacks blockchain.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Stacks NFT Escrow Contract
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-ESCROW-EXPIRED u101)
(define-constant ERR-INVALID-TRANSFER u102)

;; Contract Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ESCROW-TIMEOUT u500)  ;; Approximate 3-day timeout in blocks

;; Escrow Transaction Mapping
(define-map escrow-transactions
  {
    nft-contract: principal,
    nft-id: uint
  }
  {
    seller: principal,
    buyer: principal,
    price: uint,
    status: (string-ascii 20),
    expiry-block: uint
  }
)

;; Initialize Escrow
(define-public (create-nft-escrow 
  (nft-contract principal)
  (nft-id uint)
  (buyer principal)
  (sale-price uint)
)
  (begin
    ;; Transfer NFT to contract
    (try! (contract-call? nft-contract transfer nft-id tx-sender (as-contract tx-sender)))
    
    ;; Store Escrow Details
    (map-set escrow-transactions 
      {
        nft-contract: nft-contract, 
        nft-id: nft-id
      }
      {
        seller: tx-sender,
        buyer: buyer,
        price: sale-price,
        status: "pending",
        expiry-block: (+ block-height ESCROW-TIMEOUT)
      }
    )
    
    ;; Emit Event for Chainhook
    (print {
      notification: "nft-escrow-created",
      payload: {
        nft-contract: nft-contract,
        nft-id: nft-id,
        seller: tx-sender,
        buyer: buyer,
        price: sale-price
      }
    })
    
    (ok true)
  )
)

;; Complete NFT Transfer
(define-public (complete-nft-transfer 
  (nft-contract principal)
  (nft-id uint)
)
  (let 
    ((escrow-details (unwrap! 
      (map-get? escrow-transactions 
        {
          nft-contract: nft-contract, 
          nft-id: nft-id
        }
      ) 
      (err ERR-INVALID-TRANSFER)
    )))
    
    (asserts! 
      (is-eq (get status escrow-details) "pending") 
      (err ERR-INVALID-TRANSFER)
    )
    
    (asserts! 
      (<= block-height (get expiry-block escrow-details)) 
      (err ERR-ESCROW-EXPIRED)
    )
    
    ;; Transfer NFT to Buyer
    (try! 
      (as-contract 
        (contract-call? nft-contract transfer 
          nft-id 
          (as-contract tx-sender) 
          (get buyer escrow-details)
        )
      )
    )
    
    ;; Update Escrow Status
    (map-set escrow-transactions 
      {
        nft-contract: nft-contract, 
        nft-id: nft-id
      }
      (merge escrow-details { status: "completed" })
    )
    
    ;; Emit Completion Event
    (print {
      notification: "nft-transfer-completed",
      payload: {
        nft-contract: nft-contract,
        nft-id: nft-id,
        buyer: (get buyer escrow-details)
      }
    })
    
    (ok true)
  )
)

;; Refund Mechanism if Escrow Expires
(define-public (refund-nft 
  (nft-contract principal)
  (nft-id uint)
)
  (let 
    ((escrow-details (unwrap! 
      (map-get? escrow-transactions 
        {
          nft-contract: nft-contract, 
          nft-id: nft-id
        }
      ) 
      (err ERR-INVALID-TRANSFER)
    )))
    
    (asserts! 
      (> block-height (get expiry-block escrow-details)) 
      (err ERR-ESCROW-EXPIRED)
    )
    
    ;; Transfer NFT Back to Seller
    (try! 
      (as-contract 
        (contract-call? nft-contract transfer 
          nft-id 
          (as-contract tx-sender) 
          (get seller escrow-details)
        )
      )
    )
    
    ;; Update Escrow Status
    (map-set escrow-transactions 
      {
        nft-contract: nft-contract, 
        nft-id: nft-id
      }
      (merge escrow-details { status: "refunded" })
    )
    
    ;; Emit Refund Event
    (print {
      notification: "nft-escrow-refunded",
      payload: {
        nft-contract: nft-contract,
        nft-id: nft-id,
        seller: (get seller escrow-details)
      }
    })
    
    (ok true)
  )
)

;; Utility: Get Current Escrow Status
(define-read-only (get-escrow-status 
  (nft-contract principal)
  (nft-id uint)
)
  (map-get? escrow-transactions 
    {
      nft-contract: nft-contract, 
      nft-id: nft-id
    }
  )
)

