;; Risk-Based Premium Adjustment Contract
;; Dynamic premium adjustment based on real-time property conditions
;; Automated claims processing and risk assessment system

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-exists (err u202))
(define-constant err-invalid-policy (err u203))
(define-constant err-invalid-amount (err u204))
(define-constant err-unauthorized (err u205))
(define-constant err-insufficient-funds (err u206))
(define-constant err-policy-expired (err u207))
(define-constant err-claim-already-processed (err u208))

;; Policy status constants
(define-constant status-active u1)
(define-constant status-expired u2)
(define-constant status-cancelled u3)
(define-constant status-suspended u4)

;; Risk level constants
(define-constant risk-low u1)
(define-constant risk-medium u2)
(define-constant risk-high u3)
(define-constant risk-critical u4)

;; Claims status constants
(define-constant claim-pending u1)
(define-constant claim-approved u2)
(define-constant claim-rejected u3)
(define-constant claim-paid u4)

;; Data structures
(define-map insurance-policies
  { policy-id: (string-ascii 64) }
  {
    property-id: (string-ascii 64),
    policyholder: principal,
    coverage-amount: uint,
    base-premium: uint,
    current-premium: uint,
    risk-score: uint,
    start-date: uint,
    end-date: uint,
    status: uint,
    last-adjustment: uint
  }
)

(define-map premium-adjustments
  { policy-id: (string-ascii 64), adjustment-id: uint }
  {
    old-premium: uint,
    new-premium: uint,
    risk-factor: uint,
    adjustment-date: uint,
    reason: (string-ascii 256),
    applied-by: principal
  }
)

(define-map insurance-claims
  { claim-id: (string-ascii 64) }
  {
    policy-id: (string-ascii 64),
    claimant: principal,
    claim-amount: uint,
    incident-date: uint,
    claim-date: uint,
    status: uint,
    evidence-hash: (string-ascii 64),
    processed-by: principal,
    payout-amount: uint
  }
)

(define-map risk-assessments
  { property-id: (string-ascii 64), assessment-date: uint }
  {
    fire-risk: uint,
    flood-risk: uint,
    security-risk: uint,
    environmental-risk: uint,
    overall-score: uint,
    assessor: principal
  }
)

(define-map policy-payments
  { policy-id: (string-ascii 64), payment-id: uint }
  {
    amount: uint,
    payment-date: uint,
    payment-type: (string-ascii 32), ;; premium, claim, refund
    transaction-hash: (string-ascii 64)
  }
)

;; Data variables
(define-data-var total-policies uint u0)
(define-data-var total-claims uint u0)
(define-data-var next-adjustment-id uint u1)
(define-data-var next-payment-id uint u1)
(define-data-var insurance-fund uint u0)

;; Private functions
(define-private (is-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (calculate-risk-score 
  (fire-risk uint) 
  (flood-risk uint) 
  (security-risk uint) 
  (environmental-risk uint)
)
  ;; Weighted risk calculation: fire=30%, flood=25%, security=20%, environmental=25%
  (/ (+ (* fire-risk u30) (* flood-risk u25) (* security-risk u20) (* environmental-risk u25)) u100)
)

(define-private (calculate-premium-adjustment (base-premium uint) (risk-score uint))
  (let 
    (
      (adjustment-factor (if (<= risk-score u25)
        u80  ;; 20% discount for low risk
        (if (<= risk-score u50)
          u90  ;; 10% discount for medium-low risk
          (if (<= risk-score u75)
            u100 ;; No change for medium risk
            (if (<= risk-score u90)
              u120 ;; 20% increase for high risk
              u150 ;; 50% increase for critical risk
            )
          )
        )
      ))
    )
    (/ (* base-premium adjustment-factor) u100)
  )
)

(define-private (is-policy-active (policy-id (string-ascii 64)))
  (match (map-get? insurance-policies { policy-id: policy-id })
    policy (and 
      (is-eq (get status policy) status-active)
      (< stacks-block-height (get end-date policy))
    )
    false
  )
)

;; Public functions

;; Create new insurance policy
(define-public (create-policy
  (policy-id (string-ascii 64))
  (property-id (string-ascii 64))
  (coverage-amount uint)
  (base-premium uint)
  (duration-blocks uint)
)
  (begin
    (asserts! (is-owner) err-owner-only)
    (asserts! (is-none (map-get? insurance-policies { policy-id: policy-id })) err-already-exists)
    (asserts! (> coverage-amount u0) err-invalid-amount)
    (asserts! (> base-premium u0) err-invalid-amount)
    (asserts! (> duration-blocks u0) err-invalid-amount)
    
    (map-set insurance-policies
      { policy-id: policy-id }
      {
        property-id: property-id,
        policyholder: tx-sender,
        coverage-amount: coverage-amount,
        base-premium: base-premium,
        current-premium: base-premium,
        risk-score: u50, ;; default medium risk
        start-date: stacks-block-height,
        end-date: (+ stacks-block-height duration-blocks),
        status: status-active,
        last-adjustment: stacks-block-height
      }
    )
    
    (var-set total-policies (+ (var-get total-policies) u1))
    (ok policy-id)
  )
)

;; Assess property risk and adjust premium
(define-public (assess-risk-and-adjust-premium
  (property-id (string-ascii 64))
  (policy-id (string-ascii 64))
  (fire-risk uint)
  (flood-risk uint)
  (security-risk uint)
  (environmental-risk uint)
)
  (let 
    (
      (policy (unwrap! (map-get? insurance-policies { policy-id: policy-id }) err-not-found))
      (new-risk-score (calculate-risk-score fire-risk flood-risk security-risk environmental-risk))
      (new-premium (calculate-premium-adjustment (get base-premium policy) new-risk-score))
      (adjustment-id (var-get next-adjustment-id))
    )
    (asserts! (is-owner) err-owner-only)
    (asserts! (is-policy-active policy-id) err-invalid-policy)
    (asserts! (is-eq (get property-id policy) property-id) err-invalid-policy)
    
    ;; Record risk assessment
    (map-set risk-assessments
      { property-id: property-id, assessment-date: stacks-block-height }
      {
        fire-risk: fire-risk,
        flood-risk: flood-risk,
        security-risk: security-risk,
        environmental-risk: environmental-risk,
        overall-score: new-risk-score,
        assessor: tx-sender
      }
    )
    
    ;; Record premium adjustment
    (map-set premium-adjustments
      { policy-id: policy-id, adjustment-id: adjustment-id }
      {
        old-premium: (get current-premium policy),
        new-premium: new-premium,
        risk-factor: new-risk-score,
        adjustment-date: stacks-block-height,
        reason: "Risk assessment update",
        applied-by: tx-sender
      }
    )
    
    ;; Update policy with new premium and risk score
    (map-set insurance-policies
      { policy-id: policy-id }
      (merge policy {
        current-premium: new-premium,
        risk-score: new-risk-score,
        last-adjustment: stacks-block-height
      })
    )
    
    (var-set next-adjustment-id (+ adjustment-id u1))
    (ok new-premium)
  )
)

;; Submit insurance claim
(define-public (submit-claim
  (claim-id (string-ascii 64))
  (policy-id (string-ascii 64))
  (claim-amount uint)
  (incident-date uint)
  (evidence-hash (string-ascii 64))
)
  (let 
    (
      (policy (unwrap! (map-get? insurance-policies { policy-id: policy-id }) err-not-found))
    )
    (asserts! (is-none (map-get? insurance-claims { claim-id: claim-id })) err-already-exists)
    (asserts! (is-policy-active policy-id) err-invalid-policy)
    (asserts! (is-eq (get policyholder policy) tx-sender) err-unauthorized)
    (asserts! (> claim-amount u0) err-invalid-amount)
    (asserts! (<= claim-amount (get coverage-amount policy)) err-invalid-amount)
    (asserts! (<= incident-date stacks-block-height) err-invalid-policy)
    
    (map-set insurance-claims
      { claim-id: claim-id }
      {
        policy-id: policy-id,
        claimant: tx-sender,
        claim-amount: claim-amount,
        incident-date: incident-date,
        claim-date: stacks-block-height,
        status: claim-pending,
        evidence-hash: evidence-hash,
        processed-by: contract-owner,
        payout-amount: u0
      }
    )
    
    (var-set total-claims (+ (var-get total-claims) u1))
    (ok claim-id)
  )
)

;; Process insurance claim (owner only)
(define-public (process-claim
  (claim-id (string-ascii 64))
  (approved bool)
  (payout-amount uint)
)
  (let 
    (
      (claim (unwrap! (map-get? insurance-claims { claim-id: claim-id }) err-not-found))
      (policy (unwrap! (map-get? insurance-policies { policy-id: (get policy-id claim) }) err-not-found))
    )
    (asserts! (is-owner) err-owner-only)
    (asserts! (is-eq (get status claim) claim-pending) err-claim-already-processed)
    (asserts! (<= payout-amount (get claim-amount claim)) err-invalid-amount)
    
    (if approved
      (begin
        (asserts! (>= (var-get insurance-fund) payout-amount) err-insufficient-funds)
        (map-set insurance-claims
          { claim-id: claim-id }
          (merge claim {
            status: claim-approved,
            processed-by: tx-sender,
            payout-amount: payout-amount
          })
        )
        (var-set insurance-fund (- (var-get insurance-fund) payout-amount))
        (ok payout-amount)
      )
      (begin
        (map-set insurance-claims
          { claim-id: claim-id }
          (merge claim {
            status: claim-rejected,
            processed-by: tx-sender,
            payout-amount: u0
          })
        )
        (ok u0)
      )
    )
  )
)

;; Get policy information
(define-read-only (get-policy-info (policy-id (string-ascii 64)))
  (map-get? insurance-policies { policy-id: policy-id })
)

;; Get claim information
(define-read-only (get-claim-info (claim-id (string-ascii 64)))
  (map-get? insurance-claims { claim-id: claim-id })
)

;; Get risk assessment
(define-read-only (get-risk-assessment (property-id (string-ascii 64)) (assessment-date uint))
  (map-get? risk-assessments { property-id: property-id, assessment-date: assessment-date })
)

;; Get premium adjustment history
(define-read-only (get-premium-adjustment (policy-id (string-ascii 64)) (adjustment-id uint))
  (map-get? premium-adjustments { policy-id: policy-id, adjustment-id: adjustment-id })
)

;; Add funds to insurance pool (owner only)
(define-public (add-insurance-funds (amount uint))
  (begin
    (asserts! (is-owner) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (var-set insurance-fund (+ (var-get insurance-fund) amount))
    (ok (var-get insurance-fund))
  )
)

;; Get insurance fund balance
(define-read-only (get-insurance-fund-balance)
  (var-get insurance-fund)
)

;; Get total policies count
(define-read-only (get-total-policies)
  (var-get total-policies)
)

;; Get total claims count
(define-read-only (get-total-claims)
  (var-get total-claims)
)

;; Calculate premium for given risk factors
(define-read-only (calculate-premium 
  (base-premium uint) 
  (fire-risk uint) 
  (flood-risk uint) 
  (security-risk uint) 
  (environmental-risk uint)
)
  (let 
    (
      (risk-score (calculate-risk-score fire-risk flood-risk security-risk environmental-risk))
    )
    (calculate-premium-adjustment base-premium risk-score)
  )
)
