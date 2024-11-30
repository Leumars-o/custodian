
;; title: custodian
;; summary: A Stacks NFT Escrow Contract
;; description: Custodian is a Stacks NFT Escrow Contract that allows users to securely trade NFTs on the Stacks blockchain.

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Enhanced NFT Escrow Contract with Explicit Receipt Verification
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;; 

;; NFT Trait Definition
(define-trait nft-trait
  (
    ;; Transfer an NFT from one principal to another
    (transfer (uint principal principal) (response bool uint))
  )
)

;; Error Codes
(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-ESCROW-EXPIRED u101)
(define-constant ERR-INVALID-TRANSFER u102)
(define-constant ERR-NFT-NOT-RECEIVED u103)
(define-constant ERR-INAVALID-ADDRESS u104)
(define-constant ERR-INVALID-PRICE u105)

;; Contract Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ESCROW-TIMEOUT u500)  ;; Approximate 3-day timeout in blocks

;; NFT Receipt Tracking Mapping
(define-map nft-receipts
  {
    nft-contract: principal,
    nft-id: uint
  }
  {
    received: bool,
    received-at-block: uint
  }
)

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Core functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Logging function, Chainhook will listen to these and deal with the data
(define-public (confirm-nft-receipt 
  (nft-contract principal)
  (nft-id uint)
)
  (begin
    ;; Only seller can confirm receipt
    (asserts! (is-eq tx-sender (get seller (unwrap! 
      (map-get? escrow-transactions 
        {
          nft-contract: nft-contract, 
          nft-id: nft-id
        }
      ) 
      (err ERR-INVALID-TRANSFER)
    ))) (err ERR-NOT-AUTHORIZED))
    (asserts! (is-valid-nft-contract nft-contract) (err ERR-INAVALID-ADDRESS))
    (asserts! (> nft-id u0) (err ERR-INVALID-TRANSFER))

    ;; Mark NFT as received
    (map-set nft-receipts 
      {
        nft-contract: nft-contract,
        nft-id: nft-id
      }
      {
        received: true,
        received-at-block: block-height
      }
    )

    ;; Emit Receipt Confirmation Event
    (print {
      notification: "nft-receipt-confirmed",
      payload: {
        nft-contract: nft-contract,
        nft-id: nft-id,
        seller: tx-sender
      }
    })

    (ok true)
  )
)

;; Initialize Escrow with Enhanced Receipt Tracking
(define-public (create-nft-escrow 
  (nft-contract <nft-trait>)
  (nft-id uint)
  (buyer principal)
  (sale-price uint)
)

  (if (is-standard buyer)
    (begin
    ;; Validate buyer address
    (asserts! (is-standard buyer) (err ERR-INAVALID-ADDRESS))
    ;; Validate NFT Contract
    (asserts! (is-valid-nft-contract (contract-of nft-contract)) (err ERR-INAVALID-ADDRESS))
    ;; Validate sale price
    (asserts! (> sale-price u0) (err ERR-INVALID-PRICE))
    ;; Validate seller ownership and transfer capability
    (asserts! 
      (is-ok (contract-call? nft-contract transfer 
        nft-id 
        tx-sender 
        (as-contract tx-sender)
      )) 
      (err ERR-INVALID-TRANSFER)
    )
    ;; Check that sale price is greater than zero
    (asserts! (> sale-price u0) (err ERR-INVALID-PRICE))
    
    ;; Initialize NFT Receipt Tracking
    (map-set nft-receipts 
      {
        nft-contract: (contract-of nft-contract),
        nft-id: nft-id
      }
      {
        received: false,
        received-at-block: u0
      }
    )
    
    ;; Store Escrow Details
    (map-set escrow-transactions 
      {
        nft-contract: (contract-of nft-contract), 
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
        nft-contract: (contract-of nft-contract),
        nft-id: nft-id,
        seller: tx-sender,
        buyer: buyer,
        price: sale-price
      }
    })
    
    (ok true)
    )
    (err ERR-INAVALID-ADDRESS)
  )
)

;; Complete NFT Transfer with Receipt Verification
(define-public (complete-nft-transfer 
  (nft-contract <nft-trait>)
  (nft-id uint)
)
  (let 
    ((escrow-details (unwrap! 
      (map-get? escrow-transactions 
        {
          nft-contract: (contract-of nft-contract), 
          nft-id: nft-id
        }
      ) 
      (err ERR-INVALID-TRANSFER)
    ))
    (nft-receipt (unwrap! 
      (map-get? nft-receipts 
        {
          nft-contract: (contract-of nft-contract),
          nft-id: nft-id
        }
      ) 
      (err ERR-INVALID-TRANSFER)
    )))

    ;; Verify NFT Contract
    (asserts! (is-valid-nft-contract (contract-of nft-contract)) (err ERR-INAVALID-ADDRESS))

    ;; Verify NFT Receipt
    (asserts! 
      (get received nft-receipt) 
      (err ERR-NFT-NOT-RECEIVED)
    )
    
    ;; Verify Escrow Status and Expiry
    (asserts! 
      (is-eq (get status escrow-details) "pending") 
      (err ERR-INVALID-TRANSFER)
    )
    
    (asserts! 
      (<= block-height (get expiry-block escrow-details)) 
      (err ERR-ESCROW-EXPIRED)
    )
    
    (asserts! (> nft-id u0) (err ERR-INVALID-TRANSFER))

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
        nft-contract: (contract-of nft-contract), 
        nft-id: nft-id
      }
      (merge escrow-details { status: "completed" })
    )
    
    ;; Emit Completion Event
    (print {
      notification: "nft-transfer-completed",
      payload: {
        nft-contract: (contract-of nft-contract),
        nft-id: nft-id,
        buyer: (get buyer escrow-details)
      }
    })
    
    (ok true)
  )
)

;; Refund Mechanism if Escrow Expires
(define-public (refund-nft 
  (nft-contract <nft-trait>)
  (nft-id uint)
)
  (let 
    ((escrow-details (unwrap! 
      (map-get? escrow-transactions 
        {
          nft-contract: (contract-of nft-contract), 
          nft-id: nft-id
        }
      ) 
      (err ERR-INVALID-TRANSFER)
    )))
    
    ;; Verify NFT Contract
    (asserts! (is-valid-nft-contract (contract-of nft-contract)) (err ERR-INAVALID-ADDRESS))

    (asserts! (> nft-id u0) (err ERR-INVALID-TRANSFER))
    
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
        nft-contract: (contract-of nft-contract), 
        nft-id: nft-id
      }
      (merge escrow-details { status: "refunded" })
    )
    
    ;; Emit Refund Event
    (print {
      notification: "nft-escrow-refunded",
      payload: {
        nft-contract: (contract-of nft-contract),
        nft-id: nft-id,
        seller: (get seller escrow-details)
      }
    })
    
    (ok true)
  )
)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Setting, getting and utility functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
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
;; Utility: Get NFT Receipt Status
(define-read-only (get-nft-receipt-status 
  (nft-contract principal)
  (nft-id uint)
)
  (map-get? nft-receipts 
    {
      nft-contract: nft-contract,
      nft-id: nft-id
    }
  )
)
;; Utility: Check if Principal is a valid NFT Contract
(define-read-only (is-valid-nft-contract (contract principal))
  (match (principal-destruct? contract)
    ok-result 
      (is-some (get name ok-result))
    err-result 
      false
  )
)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; End of Contract!
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;