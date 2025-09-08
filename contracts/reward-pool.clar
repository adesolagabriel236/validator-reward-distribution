
;; title: reward-pool
;; version:
;; summary:
;; description:

;; Reward Pool Smart Contract
;; Manages the reward pool funds and pool operations

;; Constants
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_POOL_EMPTY (err u403))
(define-constant ERR_WITHDRAWAL_FAILED (err u404))
(define-constant ERR_DEPOSIT_FAILED (err u405))
(define-constant ERR_INVALID_RECIPIENT (err u406))
(define-constant ERR_POOL_FROZEN (err u407))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Maximum withdrawal per transaction (1000 STX)
(define-constant MAX_WITHDRAWAL_AMOUNT u1000000000)

;; Minimum pool balance to maintain (100 STX)
(define-constant MIN_POOL_BALANCE u100000000)

;; Data Variables
(define-data-var pool-balance uint u0)
(define-data-var total-deposits uint u0)
(define-data-var total-withdrawals uint u0)
(define-data-var is-frozen bool false)
(define-data-var admin principal CONTRACT_OWNER)
(define-data-var emergency-contact principal CONTRACT_OWNER)
(define-data-var withdrawal-fee uint u0)

;; Data Maps
(define-map authorized-callers principal bool)
(define-map deposit-history uint {
    depositor: principal,
    amount: uint,
    timestamp: uint,
    block-height: uint
})

(define-map withdrawal-history uint {
    recipient: principal,
    amount: uint,
    timestamp: uint,
    block-height: uint,
    approved-by: principal
})

(define-map user-deposits principal uint)
(define-map pending-withdrawals uint {
    recipient: principal,
    amount: uint,
    requested-by: principal,
    timestamp: uint,
    approved: bool
})

;; Counter for tracking transactions
(define-data-var deposit-counter uint u0)
(define-data-var withdrawal-counter uint u0)
(define-data-var pending-withdrawal-counter uint u0)

;; Read-only functions

;; Get current pool balance
(define-read-only (get-pool-balance)
    (var-get pool-balance)
)

;; Get total deposits
(define-read-only (get-total-deposits)
    (var-get total-deposits)
)

;; Get total withdrawals
(define-read-only (get-total-withdrawals)
    (var-get total-withdrawals)
)

;; Check if pool is frozen
(define-read-only (is-pool-frozen)
    (var-get is-frozen)
)

;; Get withdrawal fee
(define-read-only (get-withdrawal-fee)
    (var-get withdrawal-fee)
)

;; Check if caller is authorized
(define-read-only (is-authorized (caller principal))
    (default-to false (map-get? authorized-callers caller))
)

;; Get user deposit amount
(define-read-only (get-user-deposits (user principal))
    (default-to u0 (map-get? user-deposits user))
)

;; Get deposit history
(define-read-only (get-deposit-history (deposit-id uint))
    (map-get? deposit-history deposit-id)
)

;; Get withdrawal history
(define-read-only (get-withdrawal-history (withdrawal-id uint))
    (map-get? withdrawal-history withdrawal-id)
)

;; Get pending withdrawal
(define-read-only (get-pending-withdrawal (withdrawal-id uint))
    (map-get? pending-withdrawals withdrawal-id)
)

;; Calculate available balance (excluding minimum reserve)
(define-read-only (get-available-balance)
    (let (
        (current-balance (var-get pool-balance))
    )
        (if (> current-balance MIN_POOL_BALANCE)
            (- current-balance MIN_POOL_BALANCE)
            u0
        )
    )
)

;; Private functions

;; Check if caller is admin
(define-private (is-admin (caller principal))
    (is-eq caller (var-get admin))
)

;; Check if caller is emergency contact
(define-private (is-emergency-contact (caller principal))
    (is-eq caller (var-get emergency-contact))
)

;; Increment deposit counter
(define-private (increment-deposit-counter)
    (let (
        (current (var-get deposit-counter))
        (new-counter (+ current u1))
    )
        (var-set deposit-counter new-counter)
        new-counter
    )
)

;; Increment withdrawal counter
(define-private (increment-withdrawal-counter)
    (let (
        (current (var-get withdrawal-counter))
        (new-counter (+ current u1))
    )
        (var-set withdrawal-counter new-counter)
        new-counter
    )
)

;; Public functions

;; Add funds to the reward pool
(define-public (add-funds (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get is-frozen)) ERR_POOL_FROZEN)
        
        ;; Transfer STX to contract
        (match (stx-transfer? amount tx-sender (as-contract tx-sender))
            success
                (let (
                    (deposit-id (increment-deposit-counter))
                    (current-balance (var-get pool-balance))
                    (current-deposits (var-get total-deposits))
                    (current-user-deposits (get-user-deposits tx-sender))
                )
                    ;; Update balances
                    (var-set pool-balance (+ current-balance amount))
                    (var-set total-deposits (+ current-deposits amount))
                    
                    ;; Update user deposits
                    (map-set user-deposits tx-sender (+ current-user-deposits amount))
                    
                    ;; Record deposit history
                    (map-set deposit-history deposit-id {
                        depositor: tx-sender,
                        amount: amount,
                        timestamp: block-height,
                        block-height: block-height
                    })
                    
                    (ok deposit-id)
                )
            error ERR_DEPOSIT_FAILED
        )
    )
)

;; Withdraw rewards (only for authorized callers)
(define-public (withdraw-rewards (recipient principal) (amount uint))
    (begin
        (asserts! (or (is-admin tx-sender) (is-authorized tx-sender)) ERR_UNAUTHORIZED)
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount MAX_WITHDRAWAL_AMOUNT) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get is-frozen)) ERR_POOL_FROZEN)
        
        (let (
            (available-balance (get-available-balance))
            (fee (var-get withdrawal-fee))
            (total-amount (+ amount fee))
        )
            (asserts! (>= available-balance total-amount) ERR_INSUFFICIENT_FUNDS)
            
            ;; Transfer STX to recipient
            (match (as-contract (stx-transfer? amount tx-sender recipient))
                success
                    (let (
                        (withdrawal-id (increment-withdrawal-counter))
                        (current-balance (var-get pool-balance))
                        (current-withdrawals (var-get total-withdrawals))
                    )
                        ;; Update balances
                        (var-set pool-balance (- current-balance total-amount))
                        (var-set total-withdrawals (+ current-withdrawals amount))
                        
                        ;; Record withdrawal history
                        (map-set withdrawal-history withdrawal-id {
                            recipient: recipient,
                            amount: amount,
                            timestamp: block-height,
                            block-height: block-height,
                            approved-by: tx-sender
                        })
                        
                        (ok withdrawal-id)
                    )
                error ERR_WITHDRAWAL_FAILED
            )
        )
    )
)

;; Request withdrawal (creates pending withdrawal)
(define-public (request-withdrawal (amount uint))
    (begin
        (asserts! (> amount u0) ERR_INVALID_AMOUNT)
        (asserts! (<= amount MAX_WITHDRAWAL_AMOUNT) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get is-frozen)) ERR_POOL_FROZEN)
        
        (let (
            (available-balance (get-available-balance))
            (pending-id (+ (var-get pending-withdrawal-counter) u1))
        )
            (asserts! (>= available-balance amount) ERR_INSUFFICIENT_FUNDS)
            
            (var-set pending-withdrawal-counter pending-id)
            (map-set pending-withdrawals pending-id {
                recipient: tx-sender,
                amount: amount,
                requested-by: tx-sender,
                timestamp: block-height,
                approved: false
            })
            
            (ok pending-id)
        )
    )
)

;; Approve pending withdrawal
(define-public (approve-withdrawal (withdrawal-id uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (var-get is-frozen)) ERR_POOL_FROZEN)
        
        (match (get-pending-withdrawal withdrawal-id)
            withdrawal-data
                (let (
                    (recipient (get recipient withdrawal-data))
                    (amount (get amount withdrawal-data))
                )
                    (asserts! (not (get approved withdrawal-data)) ERR_UNAUTHORIZED)
                    
                    ;; Mark as approved and execute withdrawal
                    (map-set pending-withdrawals withdrawal-id
                        (merge withdrawal-data { approved: true })
                    )
                    
                    ;; Execute the withdrawal
                    (withdraw-rewards recipient amount)
                )
            ERR_INVALID_AMOUNT
        )
    )
)

;; Set withdrawal fee (admin only)
(define-public (set-withdrawal-fee (fee uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set withdrawal-fee fee)
        (ok true)
    )
)

;; Add authorized caller
(define-public (add-authorized-caller (caller principal))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (map-set authorized-callers caller true)
        (ok true)
    )
)

;; Remove authorized caller
(define-public (remove-authorized-caller (caller principal))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (map-delete authorized-callers caller)
        (ok true)
    )
)

;; Emergency freeze pool
(define-public (freeze-pool)
    (begin
        (asserts! (or (is-admin tx-sender) (is-emergency-contact tx-sender)) ERR_UNAUTHORIZED)
        (var-set is-frozen true)
        (ok true)
    )
)

;; Unfreeze pool (admin only)
(define-public (unfreeze-pool)
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set is-frozen false)
        (ok true)
    )
)

;; Transfer admin rights
(define-public (transfer-admin (new-admin principal))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set admin new-admin)
        (ok true)
    )
)

;; Set emergency contact
(define-public (set-emergency-contact (new-contact principal))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set emergency-contact new-contact)
        (ok true)
    )
)

;; token definitions
;;

;; constants
;;

;; data vars
;;

;; data maps
;;

;; public functions
;;

;; read only functions
;;

;; private functions
;;

