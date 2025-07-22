;; Human Enhancement Consent Contract
;; Ensures informed consent for irreversible human modifications

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-CONSENT-NOT-FOUND (err u401))
(define-constant ERR-INVALID-ENHANCEMENT (err u402))
(define-constant ERR-CONSENT-EXPIRED (err u403))
(define-constant ERR-GUARDIAN-REQUIRED (err u404))
(define-constant ERR-INVALID-RISK-LEVEL (err u405))

;; Data Variables
(define-data-var next-consent-id uint u1)
(define-data-var consent-validity-period uint u4320) ;; ~30 days in blocks
(define-data-var minimum-age uint u18)

;; Data Maps
(define-map enhancement-consents
  { consent-id: uint }
  {
    subject: principal,
    enhancement-type: (string-ascii 100),
    risk-level: uint,
    consent-block: uint,
    expiry-block: uint,
    is-active: bool,
    is-irreversible: bool,
    guardian-approval: (optional principal),
    medical-clearance: bool,
    psychological-evaluation: bool
  }
)

(define-map consent-modifications
  { consent-id: uint, modification-id: uint }
  {
    modifier: principal,
    modification-type: (string-ascii 50),
    modification-block: uint,
    previous-value: (string-ascii 200),
    new-value: (string-ascii 200),
    reason: (string-ascii 300)
  }
)

(define-map withdrawal-requests
  { consent-id: uint }
  {
    requester: principal,
    request-block: uint,
    reason: (string-ascii 300),
    is-processed: bool,
    processing-block: (optional uint),
    withdrawal-approved: bool
  }
)

(define-map guardian-approvals
  { subject: principal, guardian: principal }
  {
    approval-block: uint,
    relationship: (string-ascii 50),
    legal-verification: bool,
    approval-scope: (string-ascii 200),
    is-active: bool
  }
)

(define-map enhancement-procedures
  { procedure-id: (string-ascii 100) }
  {
    risk-level: uint,
    reversibility: bool,
    required-clearances: (string-ascii 200),
    minimum-consent-period: uint,
    guardian-required: bool
  }
)

(define-map consent-verification
  { consent-id: uint }
  {
    medical-officer: (optional principal),
    ethics-officer: (optional principal),
    legal-officer: (optional principal),
    verification-block: uint,
    all-verified: bool,
    verification-notes: (string-ascii 500)
  }
)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

(define-private (is-consent-valid (consent-id uint))
  (match (map-get? enhancement-consents { consent-id: consent-id })
    consent (and
             (get is-active consent)
             (> (get expiry-block consent) block-height))
    false
  )
)

;; Enhancement Procedure Registration
(define-public (register-enhancement-procedure (procedure-id (string-ascii 100)) (risk-level uint) (reversible bool) (clearances (string-ascii 200)) (consent-period uint) (guardian-required bool))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= risk-level u1) (<= risk-level u5)) ERR-INVALID-RISK-LEVEL)

    (map-set enhancement-procedures
      { procedure-id: procedure-id }
      {
        risk-level: risk-level,
        reversibility: reversible,
        required-clearances: clearances,
        minimum-consent-period: consent-period,
        guardian-required: guardian-required
      }
    )

    (ok true)
  )
)

;; Guardian Approval Management
(define-public (register-guardian-approval (subject principal) (relationship (string-ascii 50)) (approval-scope (string-ascii 200)))
  (begin
    (map-set guardian-approvals
      { subject: subject, guardian: tx-sender }
      {
        approval-block: block-height,
        relationship: relationship,
        legal-verification: false,
        approval-scope: approval-scope,
        is-active: true
      }
    )

    (ok true)
  )
)

(define-public (verify-guardian-legal-status (subject principal) (guardian principal))
  (let ((approval (unwrap! (map-get? guardian-approvals { subject: subject, guardian: guardian }) ERR-CONSENT-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)

    (map-set guardian-approvals
      { subject: subject, guardian: guardian }
      (merge approval { legal-verification: true })
    )

    (ok true)
  )
)

;; Consent Management Functions
(define-public (create-enhancement-consent (enhancement-type (string-ascii 100)) (risk-level uint) (is-irreversible bool) (guardian (optional principal)))
  (let ((consent-id (var-get next-consent-id))
        (expiry-block (+ block-height (var-get consent-validity-period))))

    (asserts! (and (>= risk-level u1) (<= risk-level u5)) ERR-INVALID-RISK-LEVEL)

    ;; Check if guardian approval is required for high-risk procedures
    (if (and (>= risk-level u4) (is-none guardian))
        ERR-GUARDIAN-REQUIRED
        (begin
          (map-set enhancement-consents
            { consent-id: consent-id }
            {
              subject: tx-sender,
              enhancement-type: enhancement-type,
              risk-level: risk-level,
              consent-block: block-height,
              expiry-block: expiry-block,
              is-active: true,
              is-irreversible: is-irreversible,
              guardian-approval: guardian,
              medical-clearance: false,
              psychological-evaluation: false
            }
          )

          (var-set next-consent-id (+ consent-id u1))
          (ok consent-id)
        )
    )
  )
)

;; Medical and Psychological Clearance
(define-public (provide-medical-clearance (consent-id uint))
  (let ((consent (unwrap! (map-get? enhancement-consents { consent-id: consent-id }) ERR-CONSENT-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)

    (map-set enhancement-consents
      { consent-id: consent-id }
      (merge consent { medical-clearance: true })
    )

    (ok true)
  )
)

(define-public (provide-psychological-evaluation (consent-id uint))
  (let ((consent (unwrap! (map-get? enhancement-consents { consent-id: consent-id }) ERR-CONSENT-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)

    (map-set enhancement-consents
      { consent-id: consent-id }
      (merge consent { psychological-evaluation: true })
    )

    (ok true)
  )
)

;; Consent Modification Functions
(define-public (modify-consent (consent-id uint) (modification-type (string-ascii 50)) (previous-value (string-ascii 200)) (new-value (string-ascii 200)) (reason (string-ascii 300)))
  (let ((consent (unwrap! (map-get? enhancement-consents { consent-id: consent-id }) ERR-CONSENT-NOT-FOUND)))
    (asserts! (is-eq (get subject consent) tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-consent-valid consent-id) ERR-CONSENT-EXPIRED)

    ;; Create modification record
    (map-set consent-modifications
      { consent-id: consent-id, modification-id: u1 }
      {
        modifier: tx-sender,
        modification-type: modification-type,
        modification-block: block-height,
        previous-value: previous-value,
        new-value: new-value,
        reason: reason
      }
    )

    (ok true)
  )
)

;; Consent Withdrawal Functions
(define-public (request-consent-withdrawal (consent-id uint) (reason (string-ascii 300)))
  (let ((consent (unwrap! (map-get? enhancement-consents { consent-id: consent-id }) ERR-CONSENT-NOT-FOUND)))
    (asserts! (is-eq (get subject consent) tx-sender) ERR-NOT-AUTHORIZED)

    (map-set withdrawal-requests
      { consent-id: consent-id }
      {
        requester: tx-sender,
        request-block: block-height,
        reason: reason,
        is-processed: false,
        processing-block: none,
        withdrawal-approved: false
      }
    )

    (ok true)
  )
)

(define-public (process-withdrawal-request (consent-id uint) (approved bool))
  (let ((withdrawal (unwrap! (map-get? withdrawal-requests { consent-id: consent-id }) ERR-CONSENT-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)

    (map-set withdrawal-requests
      { consent-id: consent-id }
      (merge withdrawal {
        is-processed: true,
        processing-block: (some block-height),
        withdrawal-approved: approved
      })
    )

    ;; If approved, deactivate the consent
    (if approved
        (let ((consent (unwrap! (map-get? enhancement-consents { consent-id: consent-id }) ERR-CONSENT-NOT-FOUND)))
          (map-set enhancement-consents
            { consent-id: consent-id }
            (merge consent { is-active: false })
          )
          (ok true)
        )
        (ok true)
    )
  )
)

;; Verification Functions
(define-public (verify-consent (consent-id uint) (medical-officer (optional principal)) (ethics-officer (optional principal)) (legal-officer (optional principal)) (notes (string-ascii 500)))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)

    (let ((all-verified (and (is-some medical-officer) (is-some ethics-officer) (is-some legal-officer))))
      (map-set consent-verification
        { consent-id: consent-id }
        {
          medical-officer: medical-officer,
          ethics-officer: ethics-officer,
          legal-officer: legal-officer,
          verification-block: block-height,
          all-verified: all-verified,
          verification-notes: notes
        }
      )

      (ok all-verified)
    )
  )
)

;; Read-only Functions
(define-read-only (get-enhancement-consent (consent-id uint))
  (map-get? enhancement-consents { consent-id: consent-id })
)

(define-read-only (get-consent-modification (consent-id uint) (modification-id uint))
  (map-get? consent-modifications { consent-id: consent-id, modification-id: modification-id })
)

(define-read-only (get-withdrawal-request (consent-id uint))
  (map-get? withdrawal-requests { consent-id: consent-id })
)

(define-read-only (get-guardian-approval (subject principal) (guardian principal))
  (map-get? guardian-approvals { subject: subject, guardian: guardian })
)

(define-read-only (get-enhancement-procedure (procedure-id (string-ascii 100)))
  (map-get? enhancement-procedures { procedure-id: procedure-id })
)

(define-read-only (get-consent-verification (consent-id uint))
  (map-get? consent-verification { consent-id: consent-id })
)

(define-read-only (is-consent-fully-verified (consent-id uint))
  (match (map-get? consent-verification { consent-id: consent-id })
    verification (get all-verified verification)
    false
  )
)

(define-read-only (check-consent-validity (consent-id uint))
  (is-consent-valid consent-id)
)
