
;; title: NFT Auction Contract
;; description: This contract enables competitive bidding for NFTs with timed auctions

;; traits
;;
(impl-trait .custodian.nft-trait)

;; token definitions
;;


;; constants
;;
(define-constant ERR-NOT-AUTHORIZED (err u1000))
(define-constant ERR-AUCTION-EXISTS (err u1001))
(define-constant ERR-NO-AUCTION (err u1002))
(define-constant ERR-AUCTION-ENDED (err u1003))
(define-constant ERR-BID-TOO-LOW (err u1004))
(define-constant ERR-AUCTION-ACTIVE (err u1005))

;; data vars
;;
(define-data-var auction-nonce uint u0)

;; data maps
;;
(define-map auctions
    { auction-id: uint }
    {
        nft-contract:principal,
        nft-id: uint,
        seller: principal,
        start-price: uint,
        reserve-price: uint,
        min-increment: uint,
        end-block: uint,
        highest-bid: uint,
        highest-bidder: (optional principal),
        status: (string-ascii 20)
    }
)

(define-map bids
 { auction-id: uint, bidder: principal } 
 { amount: uint }
)

;; Read-only functions
(define-read-only (get-bid (auction-id uint) (bidder principal))
  (map-get? bids { auction-id: auction-id, bidder: bidder })
)

;; public functions
;;
(define-public (create-auction (nft-contract principal) 
                             (nft-id uint)
                             (start-price uint)
                             (reserve-price uint)
                             (min-increment uint)
                             (duration uint))
  (let 
    (
      (auction-id (+ (var-get auction-nonce) u1))
      (end-block (+ block-height duration))
    )
    (try! (contract-call? nft-contract transfer nft-id tx-sender (as-contract tx-sender)))
    
    (map-set auctions
      { auction-id: auction-id }
      {
        nft-contract: nft-contract,
        nft-id: nft-id,
        seller: tx-sender,
        start-price: start-price,
        reserve-price: reserve-price,
        min-increment: min-increment,
        end-block: end-block,
        highest-bid: u0,
        highest-bidder: none,
        status: "active"
      }
    )
    
    (var-set auction-nonce auction-id)
    (ok auction-id)
  )
)

(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let
    (
      (auction (unwrap! (get-auction auction-id) ERR-NO-AUCTION))
    )
    
    (asserts! (is-eq (get status auction) "active") ERR-AUCTION-ENDED)
    (asserts! (<= block-height (get end-block auction)) ERR-AUCTION-ENDED)
    (asserts! (>= bid-amount (+ (get start-price auction) 
                               (get min-increment auction))) ERR-BID-TOO-LOW)
    (asserts! (> bid-amount (get highest-bid auction)) ERR-BID-TOO-LOW)
    
    (map-set auctions auction-id
      (merge auction {
        highest-bid: bid-amount,
        highest-bidder: (some tx-sender)
      })
    )
    
    (ok true)
  )
)

(define-public (end-auction (auction-id uint))
  (let
    (
      (auction-details (unwrap! (get-auction auction-id) ERR-NO-AUCTION))
      (winner (unwrap! (get highest-bidder auction-details) ERR-NO-AUCTION))
      (custodian-principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.custodian)
    )
    
    (asserts! (> block-height (get end-block auction-details)) ERR-AUCTION-ACTIVE)
    (asserts! (is-eq (get status auction-details) "active") ERR-AUCTION-ENDED)
    
    (if (>= (get highest-bid auction-details) (get reserve-price auction-details))
        (begin
          (try! (contract-call? custodian-principal create-nft-escrow
            (get nft-contract auction-details)
            (get nft-id auction-details)
            winner
            (get highest-bid auction-details)
          ))
          
          (map-set auctions auction-id
            (merge auction-details {
              status: "in-escrow"
            })
          )
          
          (ok true)
        )
        (begin
          (try! (as-contract
            (contract-call?
              (get nft-contract auction-details)
              transfer
              (get nft-id auction-details)
              (as-contract tx-sender)
              (get seller auction-details)
            )
          ))
          
          (map-set auctions auction-id
            (merge auction-details {
              status: "cancelled"
            })
          )
          
          (ok true)
        )
    )
  )
)

;; function to get auction details
(define-read-only (get-auction (auction-id uint))
  (map-get? auctions { auction-id: auction-id })
)

;; private functions
;;
(define-private (nft-owner? (nft-contract principal) (nft-id uint))
  (unwrap! (contract-call? nft-contract get-owner nft-id) tx-sender)
)

