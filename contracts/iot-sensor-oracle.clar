;; IoT Sensor Oracle Contract
;; Integration with smart home sensors for fire, flood, and security monitoring
;; Provides real-time data collection and validation for property insurance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-sensor (err u103))
(define-constant err-invalid-data (err u104))
(define-constant err-unauthorized (err u105))

;; Sensor types
(define-constant sensor-fire u1)
(define-constant sensor-flood u2)
(define-constant sensor-security u3)
(define-constant sensor-environmental u4)

;; Data structures
(define-map sensors
  { sensor-id: (string-ascii 64) }
  {
    property-id: (string-ascii 64),
    sensor-type: uint,
    location: (string-ascii 128),
    status: uint,  ;; 1=active, 2=inactive, 3=maintenance
    last-update: uint,
    owner: principal,
    installation-date: uint
  }
)

(define-map sensor-data
  { sensor-id: (string-ascii 64), timestamp: uint }
  {
    value: uint,
    data-type: (string-ascii 32),
    validated: bool,
    validator: principal
  }
)

(define-map property-sensors
  { property-id: (string-ascii 64) }
  { sensor-count: uint, active-sensors: uint }
)

(define-map authorized-validators
  { validator: principal }
  { active: bool, authorization-date: uint }
)

;; Data variables
(define-data-var total-sensors uint u0)
(define-data-var next-sensor-id uint u1)

;; Private functions
(define-private (is-owner)
  (is-eq tx-sender contract-owner)
)

(define-private (is-authorized-validator (validator principal))
  (default-to false 
    (get active (map-get? authorized-validators { validator: validator }))
  )
)

(define-private (is-valid-sensor-type (sensor-type uint))
  (or 
    (is-eq sensor-type sensor-fire)
    (or 
      (is-eq sensor-type sensor-flood)
      (or 
        (is-eq sensor-type sensor-security)
        (is-eq sensor-type sensor-environmental)
      )
    )
  )
)

(define-private (update-property-sensor-count (property-id (string-ascii 64)) (increment bool))
  (let 
    (
      (current-data (default-to 
        { sensor-count: u0, active-sensors: u0 }
        (map-get? property-sensors { property-id: property-id })
      ))
    )
    (map-set property-sensors
      { property-id: property-id }
      {
        sensor-count: (if increment 
          (+ (get sensor-count current-data) u1)
          (- (get sensor-count current-data) u1)
        ),
        active-sensors: (get active-sensors current-data)
      }
    )
  )
)

;; Public functions

;; Register a new IoT sensor
(define-public (register-sensor 
  (sensor-id (string-ascii 64))
  (property-id (string-ascii 64))
  (sensor-type uint)
  (location (string-ascii 128))
)
  (begin
    (asserts! (is-owner) err-owner-only)
    (asserts! (is-none (map-get? sensors { sensor-id: sensor-id })) err-already-exists)
    (asserts! (is-valid-sensor-type sensor-type) err-invalid-sensor)
    (asserts! (> (len sensor-id) u0) err-invalid-data)
    (asserts! (> (len property-id) u0) err-invalid-data)
    
    (map-set sensors
      { sensor-id: sensor-id }
      {
        property-id: property-id,
        sensor-type: sensor-type,
        location: location,
        status: u1, ;; active
        last-update: stacks-block-height,
        owner: tx-sender,
        installation-date: stacks-block-height
      }
    )
    
    (update-property-sensor-count property-id true)
    (var-set total-sensors (+ (var-get total-sensors) u1))
    (ok sensor-id)
  )
)

;; Update sensor data from IoT device
(define-public (update-sensor-data
  (sensor-id (string-ascii 64))
  (value uint)
  (data-type (string-ascii 32))
)
  (let 
    (
      (sensor (unwrap! (map-get? sensors { sensor-id: sensor-id }) err-not-found))
      (timestamp stacks-block-height)
    )
    (asserts! (is-eq (get owner sensor) tx-sender) err-unauthorized)
    (asserts! (is-eq (get status sensor) u1) err-invalid-sensor) ;; must be active
    
    (map-set sensor-data
      { sensor-id: sensor-id, timestamp: timestamp }
      {
        value: value,
        data-type: data-type,
        validated: false,
        validator: contract-owner
      }
    )
    
    ;; Update sensor last-update timestamp
    (map-set sensors
      { sensor-id: sensor-id }
      (merge sensor { last-update: stacks-block-height })
    )
    
    (ok timestamp)
  )
)

;; Validate sensor data (authorized validators only)
(define-public (validate-sensor-data
  (sensor-id (string-ascii 64))
  (timestamp uint)
  (is-valid bool)
)
  (begin
    (asserts! (or (is-owner) (is-authorized-validator tx-sender)) err-unauthorized)
    (asserts! (is-some (map-get? sensor-data { sensor-id: sensor-id, timestamp: timestamp })) err-not-found)
    
    (map-set sensor-data
      { sensor-id: sensor-id, timestamp: timestamp }
      (merge 
        (unwrap-panic (map-get? sensor-data { sensor-id: sensor-id, timestamp: timestamp }))
        { validated: is-valid, validator: tx-sender }
      )
    )
    (ok true)
  )
)

;; Get sensor information
(define-read-only (get-sensor-info (sensor-id (string-ascii 64)))
  (map-get? sensors { sensor-id: sensor-id })
)

;; Get sensor data by timestamp
(define-read-only (get-sensor-data (sensor-id (string-ascii 64)) (timestamp uint))
  (map-get? sensor-data { sensor-id: sensor-id, timestamp: timestamp })
)

;; Get property sensor summary
(define-read-only (get-property-sensors (property-id (string-ascii 64)))
  (map-get? property-sensors { property-id: property-id })
)

;; Update sensor status (owner only)
(define-public (update-sensor-status
  (sensor-id (string-ascii 64))
  (new-status uint)
)
  (let 
    (
      (sensor (unwrap! (map-get? sensors { sensor-id: sensor-id }) err-not-found))
    )
    (asserts! (is-owner) err-owner-only)
    (asserts! (<= new-status u3) err-invalid-data) ;; valid status values
    (asserts! (> new-status u0) err-invalid-data)
    
    (map-set sensors
      { sensor-id: sensor-id }
      (merge sensor { status: new-status })
    )
    (ok true)
  )
)

;; Authorize validator
(define-public (authorize-validator (validator principal))
  (begin
    (asserts! (is-owner) err-owner-only)
    (map-set authorized-validators
      { validator: validator }
      { active: true, authorization-date: stacks-block-height }
    )
    (ok true)
  )
)

;; Revoke validator authorization
(define-public (revoke-validator (validator principal))
  (begin
    (asserts! (is-owner) err-owner-only)
    (map-set authorized-validators
      { validator: validator }
      (merge 
        (default-to { active: false, authorization-date: u0 }
          (map-get? authorized-validators { validator: validator })
        )
        { active: false }
      )
    )
    (ok true)
  )
)

;; Get total sensors count
(define-read-only (get-total-sensors)
  (var-get total-sensors)
)

;; Check if validator is authorized
(define-read-only (is-validator-authorized (validator principal))
  (is-authorized-validator validator)
)
