
;; title: distribution-calculator
;; version:
;; summary:
;; description:

;; Distribution Calculator Smart Contract
;; Handles reward calculation logic and distribution mechanics for validators

;; Constants
(define-constant ERR_UNAUTHORIZED (err u401))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_VALIDATOR_NOT_FOUND (err u404))
(define-constant ERR_INSUFFICIENT_BALANCE (err u402))
(define-constant ERR_INVALID_PERFORMANCE (err u403))
(define-constant ERR_CALCULATION_ERROR (err u500))
(define-constant ERR_DISTRIBUTION_FAILED (err u501))

;; Contract owner
(define-constant CONTRACT_OWNER tx-sender)

;; Minimum performance threshold (80%)
(define-constant MIN_PERFORMANCE_THRESHOLD u80)

;; Maximum bonus multiplier (150%)
(define-constant MAX_BONUS_MULTIPLIER u150)

;; Base reward rate (100 STX per period)
(define-constant BASE_REWARD_RATE u100000000)

;; Data Variables
(define-data-var total-distributed uint u0)
(define-data-var distribution-period uint u1)
(define-data-var is-paused bool false)
(define-data-var admin principal CONTRACT_OWNER)

;; Data Maps
(define-map validators principal {
    stake-amount: uint,
    performance-score: uint,
    last-distribution: uint,
    total-rewards: uint,
    is-active: bool
})

(define-map distribution-history uint {
    period: uint,
    total-amount: uint,
    validator-count: uint,
    timestamp: uint
})

(define-map validator-rewards { validator: principal, period: uint } {
    base-reward: uint,
    performance-bonus: uint,
    total-reward: uint,
    distributed: bool
})

;; Read-only functions

;; Get validator information
(define-read-only (get-validator-info (validator principal))
    (map-get? validators validator)
)

;; Get current distribution period
(define-read-only (get-current-period)
    (var-get distribution-period)
)

;; Get total distributed amount
(define-read-only (get-total-distributed)
    (var-get total-distributed)
)

;; Check if contract is paused
(define-read-only (is-contract-paused)
    (var-get is-paused)
)

;; Get distribution history for a period
(define-read-only (get-distribution-history (period uint))
    (map-get? distribution-history period)
)

;; Get validator reward for specific period
(define-read-only (get-validator-reward (validator principal) (period uint))
    (map-get? validator-rewards { validator: validator, period: period })
)

;; Calculate base reward based on stake
(define-read-only (calculate-base-reward (stake-amount uint))
    (let (
        (reward (/ (* BASE_REWARD_RATE stake-amount) u1000000))
    )
        (ok reward)
    )
)

;; Calculate performance bonus
(define-read-only (calculate-performance-bonus (base-reward uint) (performance uint))
    (if (>= performance MIN_PERFORMANCE_THRESHOLD)
        (let (
            (bonus-multiplier (if (<= performance MAX_BONUS_MULTIPLIER) performance MAX_BONUS_MULTIPLIER))
            (bonus (/ (* base-reward (- bonus-multiplier u100)) u100))
        )
            (ok bonus)
        )
        (ok u0)
    )
)

;; Calculate total validator share
(define-read-only (get-validator-share (validator principal))
    (match (get-validator-info validator)
        validator-data 
            (let (
                (stake (get stake-amount validator-data))
                (performance (get performance-score validator-data))
                (base-reward (unwrap-panic (calculate-base-reward stake)))
                (bonus (unwrap-panic (calculate-performance-bonus base-reward performance)))
            )
                (ok (+ base-reward bonus))
            )
        ERR_VALIDATOR_NOT_FOUND
    )
)

;; Private functions

;; Check if caller is admin
(define-private (is-admin (caller principal))
    (is-eq caller (var-get admin))
)

;; Update distribution period
(define-private (increment-period)
    (var-set distribution-period (+ (var-get distribution-period) u1))
)

;; Public functions

;; Register a new validator
(define-public (register-validator (validator principal) (stake-amount uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (> stake-amount u0) ERR_INVALID_AMOUNT)
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (map-set validators validator {
            stake-amount: stake-amount,
            performance-score: u100,
            last-distribution: u0,
            total-rewards: u0,
            is-active: true
        })
        (ok true)
    )
)

;; Update validator performance score
(define-public (update-performance (validator principal) (performance uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (<= performance u200) ERR_INVALID_PERFORMANCE)
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-validator-info validator)
            validator-data
                (begin
                    (map-set validators validator 
                        (merge validator-data { performance-score: performance })
                    )
                    (ok true)
                )
            ERR_VALIDATOR_NOT_FOUND
        )
    )
)

;; Calculate and record rewards for a validator
(define-public (calculate-rewards (validator principal))
    (begin
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-validator-info validator)
            validator-data
                (if (get is-active validator-data)
                    (let (
                        (current-period (var-get distribution-period))
                        (stake (get stake-amount validator-data))
                        (performance (get performance-score validator-data))
                        (base-reward (unwrap-panic (calculate-base-reward stake)))
                        (bonus (unwrap-panic (calculate-performance-bonus base-reward performance)))
                        (total-reward (+ base-reward bonus))
                    )
                        (map-set validator-rewards 
                            { validator: validator, period: current-period }
                            {
                                base-reward: base-reward,
                                performance-bonus: bonus,
                                total-reward: total-reward,
                                distributed: false
                            }
                        )
                        (ok total-reward)
                    )
                    ERR_VALIDATOR_NOT_FOUND
                )
            ERR_VALIDATOR_NOT_FOUND
        )
    )
)

;; Mark rewards as distributed for a validator
(define-public (mark-distributed (validator principal) (period uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (match (get-validator-reward validator period)
            reward-data
                (begin
                    (map-set validator-rewards 
                        { validator: validator, period: period }
                        (merge reward-data { distributed: true })
                    )
                    
                    ;; Update validator total rewards
                    (match (get-validator-info validator)
                        validator-data
                            (let (
                                (total-reward (get total-reward reward-data))
                                (new-total (+ (get total-rewards validator-data) total-reward))
                            )
                                (map-set validators validator
                                    (merge validator-data 
                                        { 
                                            total-rewards: new-total,
                                            last-distribution: period
                                        }
                                    )
                                )
                                
                                ;; Update global distributed amount
                                (var-set total-distributed 
                                    (+ (var-get total-distributed) total-reward)
                                )
                                (ok true)
                            )
                        ERR_VALIDATOR_NOT_FOUND
                    )
                )
            ERR_VALIDATOR_NOT_FOUND
        )
    )
)

;; Finalize distribution period
(define-public (finalize-period (total-amount uint) (validator-count uint))
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (asserts! (not (var-get is-paused)) ERR_UNAUTHORIZED)
        
        (let (
            (current-period (var-get distribution-period))
        )
            (map-set distribution-history current-period {
                period: current-period,
                total-amount: total-amount,
                validator-count: validator-count,
                timestamp: block-height
            })
            
            (increment-period)
            (ok current-period)
        )
    )
)

;; Emergency pause
(define-public (pause-contract)
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set is-paused true)
        (ok true)
    )
)

;; Resume contract
(define-public (resume-contract)
    (begin
        (asserts! (is-admin tx-sender) ERR_UNAUTHORIZED)
        (var-set is-paused false)
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
