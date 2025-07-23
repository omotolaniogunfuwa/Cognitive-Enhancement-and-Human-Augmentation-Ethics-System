;; Brain-Computer Interface Safety Contract
;; Governs development and deployment of neural enhancement technologies

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-DEVICE-EXISTS (err u101))
(define-constant ERR-DEVICE-NOT-FOUND (err u102))
(define-constant ERR-INVALID-PHASE (err u103))
(define-constant ERR-SAFETY-VIOLATION (err u104))
(define-constant ERR-INVALID-SEVERITY (err u105))

;; Data Variables
(define-data-var next-device-id uint u1)
(define-data-var safety-threshold uint u95)

;; Data Maps
(define-map device-registry
  { device-id: uint }
  {
    manufacturer: principal,
    device-name: (string-ascii 100),
    registration-block: uint,
    safety-score: uint,
    is-approved: bool,
    testing-phase: uint
  }
)

(define-map safety-incidents
  { incident-id: uint }
  {
    device-id: uint,
    reporter: principal,
    severity: uint,
    description: (string-ascii 500),
    report-block: uint,
    is-resolved: bool
  }
)

(define-map testing-phases
  { device-id: uint, phase: uint }
  {
    start-block: uint,
    end-block: (optional uint),
    is-completed: bool,
    test-results: uint
  }
)

(define-data-var next-incident-id uint u1)

;; Authorization Functions
(define-private (is-contract-owner)
  (is-eq tx-sender CONTRACT-OWNER)
)

;; Device Registration Functions
(define-public (register-device (manufacturer principal) (device-name (string-ascii 100)))
  (let ((device-id (var-get next-device-id)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? device-registry { device-id: device-id })) ERR-DEVICE-EXISTS)

    (map-set device-registry
      { device-id: device-id }
      {
        manufacturer: manufacturer,
        device-name: device-name,
        registration-block: block-height,
        safety-score: u0,
        is-approved: false,
        testing-phase: u0
      }
    )

    (var-set next-device-id (+ device-id u1))
    (ok device-id)
  )
)

;; Testing Phase Management
(define-public (start-testing-phase (device-id uint) (phase uint))
  (let ((device (unwrap! (map-get? device-registry { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= phase u1) (<= phase u5)) ERR-INVALID-PHASE)

    (map-set testing-phases
      { device-id: device-id, phase: phase }
      {
        start-block: block-height,
        end-block: none,
        is-completed: false,
        test-results: u0
      }
    )

    (map-set device-registry
      { device-id: device-id }
      (merge device { testing-phase: phase })
    )

    (ok true)
  )
)

(define-public (complete-testing-phase (device-id uint) (phase uint) (test-results uint))
  (let ((phase-data (unwrap! (map-get? testing-phases { device-id: device-id, phase: phase }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= test-results u0) (<= test-results u100)) ERR-INVALID-SEVERITY)

    (map-set testing-phases
      { device-id: device-id, phase: phase }
      (merge phase-data {
        end-block: (some block-height),
        is-completed: true,
        test-results: test-results
      })
    )

    (ok true)
  )
)

;; Safety Incident Reporting
(define-public (report-safety-incident (device-id uint) (severity uint) (description (string-ascii 500)))
  (let ((incident-id (var-get next-incident-id)))
    (asserts! (is-some (map-get? device-registry { device-id: device-id })) ERR-DEVICE-NOT-FOUND)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-SEVERITY)

    (map-set safety-incidents
      { incident-id: incident-id }
      {
        device-id: device-id,
        reporter: tx-sender,
        severity: severity,
        description: description,
        report-block: block-height,
        is-resolved: false
      }
    )

    (var-set next-incident-id (+ incident-id u1))
    (ok incident-id)
  )
)

;; Device Approval Functions
(define-public (approve-device (device-id uint) (safety-score uint))
  (let ((device (unwrap! (map-get? device-registry { device-id: device-id }) ERR-DEVICE-NOT-FOUND)))
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (>= safety-score (var-get safety-threshold)) ERR-SAFETY-VIOLATION)

    (map-set device-registry
      { device-id: device-id }
      (merge device {
        safety-score: safety-score,
        is-approved: true
      })
    )

    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-device-info (device-id uint))
  (map-get? device-registry { device-id: device-id })
)

(define-read-only (get-safety-incident (incident-id uint))
  (map-get? safety-incidents { incident-id: incident-id })
)

(define-read-only (get-testing-phase-info (device-id uint) (phase uint))
  (map-get? testing-phases { device-id: device-id, phase: phase })
)

(define-read-only (get-safety-threshold)
  (var-get safety-threshold)
)

(define-read-only (is-device-approved (device-id uint))
  (match (map-get? device-registry { device-id: device-id })
    device (get is-approved device)
    false
  )
)
