;; Carbon Credits Contract
;; Decentralized Carbon Credit Management and Trading System

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u200))
(define-constant ERR-NOT-AUTHORIZED (err u201))
(define-constant ERR-INVALID-AMOUNT (err u202))
(define-constant ERR-CREDIT-NOT-FOUND (err u203))
(define-constant ERR-ALREADY-RETIRED (err u204))
(define-constant ERR-INSUFFICIENT-BALANCE (err u205))
(define-constant ERR-INVALID-RECIPIENT (err u206))
(define-constant ERR-SELF-TRANSFER (err u207))
(define-constant ERR-INVALID-VERIFICATION (err u208))
(define-constant ERR-PROJECT-NOT-FOUND (err u209))
(define-constant ERR-ALREADY-VERIFIED (err u210))
(define-constant ERR-INVALID-METADATA (err u211))
(define-constant CREDIT-DECIMALS u6) ;; 1 ton CO2 = 1,000,000 micro-credits
(define-constant MAX-SUPPLY u1000000000000) ;; 1 billion tons CO2 equivalent
(define-constant MIN-MINT-AMOUNT u1000000) ;; Minimum 1 ton

;; Data Variables
(define-data-var next-credit-id uint u1)
(define-data-var next-project-id uint u1)
(define-data-var total-credits-minted uint u0)
(define-data-var total-credits-retired uint u0)
(define-data-var authorized-verifiers uint u0)

;; Data Maps
(define-map carbon-credits
    { credit-id: uint }
    {
        project-id: uint,
        owner: principal,
        amount: uint,
        vintage-year: uint,
        methodology: (string-ascii 128),
        verification-standard: (string-ascii 64),
        is-retired: bool,
        minted-at: uint,
        retired-at: (optional uint),
        retirement-reason: (optional (string-ascii 256))
    }
)

(define-map carbon-projects
    { project-id: uint }
    {
        name: (string-ascii 256),
        location: (string-ascii 128),
        project-type: (string-ascii 64),
        developer: principal,
        verification-body: (string-ascii 128),
        total-credits-issued: uint,
        project-status: (string-ascii 32),
        registry-id: (string-ascii 128),
        created-at: uint,
        verified-at: (optional uint)
    }
)

(define-map credit-balances
    { owner: principal }
    { 
        available-credits: uint,
        retired-credits: uint,
        last-updated: uint
    }
)

(define-map project-allowances
    { project-id: uint, spender: principal }
    { 
        allowed-amount: uint,
        expires-at: uint
    }
)

(define-map verified-registries
    { registry-name: (string-ascii 64) }
    {
        is-active: bool,
        verification-requirements: (string-ascii 256),
        created-at: uint
    }
)

(define-map authorized-verifiers-map
    { verifier: principal }
    {
        is-active: bool,
        verification-count: uint,
        authorized-at: uint
    }
)

(define-map credit-transfers
    { transfer-id: uint }
    {
        from: principal,
        to: principal,
        amount: uint,
        credit-id: uint,
        timestamp: uint,
        transfer-type: (string-ascii 32)
    }
)

;; Public Functions

;; Register a new carbon project
(define-public (register-project (name (string-ascii 256)) (location (string-ascii 128)) 
                                (project-type (string-ascii 64)) (verification-body (string-ascii 128)) 
                                (registry-id (string-ascii 128)))
    (let (
        (project-id (var-get next-project-id))
        (current-block stacks-block-height)
    )
        (asserts! (> (len name) u0) ERR-INVALID-METADATA)
        (asserts! (> (len location) u0) ERR-INVALID-METADATA)
        (asserts! (> (len project-type) u0) ERR-INVALID-METADATA)
        
        (map-set carbon-projects
            {project-id: project-id}
            {
                name: name,
                location: location,
                project-type: project-type,
                developer: tx-sender,
                verification-body: verification-body,
                total-credits-issued: u0,
                project-status: "pending",
                registry-id: registry-id,
                created-at: current-block,
                verified-at: none
            }
        )
        
        (var-set next-project-id (+ project-id u1))
        (ok project-id)
    )
)

;; Verify a carbon project (only authorized verifiers)
(define-public (verify-project (project-id uint))
    (let (
        (project (unwrap! (map-get? carbon-projects {project-id: project-id}) ERR-PROJECT-NOT-FOUND))
        (verifier-data (unwrap! (map-get? authorized-verifiers-map {verifier: tx-sender}) ERR-NOT-AUTHORIZED))
        (current-block stacks-block-height)
    )
        (asserts! (get is-active verifier-data) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get project-status project) "pending") ERR-ALREADY-VERIFIED)
        
        (map-set carbon-projects
            {project-id: project-id}
            (merge project {
                project-status: "verified",
                verified-at: (some current-block)
            })
        )
        
        ;; Update verifier stats
        (map-set authorized-verifiers-map
            {verifier: tx-sender}
            (merge verifier-data {
                verification-count: (+ (get verification-count verifier-data) u1)
            })
        )
        
        (ok true)
    )
)

;; Mint carbon credits for a verified project
(define-public (mint-credits (project-id uint) (amount uint) (vintage-year uint) 
                            (methodology (string-ascii 128)) (verification-standard (string-ascii 64)))
    (let (
        (project (unwrap! (map-get? carbon-projects {project-id: project-id}) ERR-PROJECT-NOT-FOUND))
        (credit-id (var-get next-credit-id))
        (current-block stacks-block-height)
        (new-total (+ (var-get total-credits-minted) amount))
    )
        (asserts! (is-eq (get developer project) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get project-status project) "verified") ERR-INVALID-VERIFICATION)
        (asserts! (>= amount MIN-MINT-AMOUNT) ERR-INVALID-AMOUNT)
        (asserts! (<= new-total MAX-SUPPLY) ERR-INVALID-AMOUNT)
        (asserts! (> vintage-year u2000) ERR-INVALID-METADATA)
        (asserts! (<= vintage-year u2100) ERR-INVALID-METADATA)
        
        ;; Create credit record
        (map-set carbon-credits
            {credit-id: credit-id}
            {
                project-id: project-id,
                owner: tx-sender,
                amount: amount,
                vintage-year: vintage-year,
                methodology: methodology,
                verification-standard: verification-standard,
                is-retired: false,
                minted-at: current-block,
                retired-at: none,
                retirement-reason: none
            }
        )
        
        ;; Update balances
        (match (map-get? credit-balances {owner: tx-sender})
            existing-balance
            (map-set credit-balances
                {owner: tx-sender}
                (merge existing-balance {
                    available-credits: (+ (get available-credits existing-balance) amount),
                    last-updated: current-block
                })
            )
            (map-set credit-balances
                {owner: tx-sender}
                {
                    available-credits: amount,
                    retired-credits: u0,
                    last-updated: current-block
                }
            )
        )
        
        ;; Update project stats
        (map-set carbon-projects
            {project-id: project-id}
            (merge project {
                total-credits-issued: (+ (get total-credits-issued project) amount)
            })
        )
        
        ;; Update global stats
        (var-set total-credits-minted new-total)
        (var-set next-credit-id (+ credit-id u1))
        
        (ok credit-id)
    )
)

;; Transfer credits between parties
(define-public (transfer-credits (recipient principal) (amount uint) (credit-id uint))
    (let (
        (credit (unwrap! (map-get? carbon-credits {credit-id: credit-id}) ERR-CREDIT-NOT-FOUND))
        (sender tx-sender)
        (sender-balance (unwrap! (map-get? credit-balances {owner: sender}) ERR-INSUFFICIENT-BALANCE))
        (current-block stacks-block-height)
    )
        (asserts! (not (is-eq sender recipient)) ERR-SELF-TRANSFER)
        (asserts! (is-eq (get owner credit) sender) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-retired credit)) ERR-ALREADY-RETIRED)
        (asserts! (>= (get available-credits sender-balance) amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        
        ;; Update sender balance
        (map-set credit-balances
            {owner: sender}
            (merge sender-balance {
                available-credits: (- (get available-credits sender-balance) amount),
                last-updated: current-block
            })
        )
        
        ;; Update recipient balance
        (match (map-get? credit-balances {owner: recipient})
            existing-balance
            (map-set credit-balances
                {owner: recipient}
                (merge existing-balance {
                    available-credits: (+ (get available-credits existing-balance) amount),
                    last-updated: current-block
                })
            )
            (map-set credit-balances
                {owner: recipient}
                {
                    available-credits: amount,
                    retired-credits: u0,
                    last-updated: current-block
                }
            )
        )
        
        ;; Update credit ownership if transferring full amount
        (if (is-eq amount (get amount credit))
            (map-set carbon-credits
                {credit-id: credit-id}
                (merge credit {owner: recipient})
            )
            true ;; Partial transfer, ownership remains with sender
        )
        
        (ok true)
    )
)

;; Retire credits for carbon offsetting
(define-public (retire-credits (credit-id uint) (amount uint) (reason (string-ascii 256)))
    (let (
        (credit (unwrap! (map-get? carbon-credits {credit-id: credit-id}) ERR-CREDIT-NOT-FOUND))
        (owner-balance (unwrap! (map-get? credit-balances {owner: tx-sender}) ERR-INSUFFICIENT-BALANCE))
        (current-block stacks-block-height)
    )
        (asserts! (is-eq (get owner credit) tx-sender) ERR-NOT-AUTHORIZED)
        (asserts! (not (get is-retired credit)) ERR-ALREADY-RETIRED)
        (asserts! (>= (get available-credits owner-balance) amount) ERR-INSUFFICIENT-BALANCE)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (> (len reason) u0) ERR-INVALID-METADATA)
        
        ;; Update credit as retired if full amount
        (if (is-eq amount (get amount credit))
            (map-set carbon-credits
                {credit-id: credit-id}
                (merge credit {
                    is-retired: true,
                    retired-at: (some current-block),
                    retirement-reason: (some reason)
                })
            )
            true ;; Partial retirement
        )
        
        ;; Update owner balance
        (map-set credit-balances
            {owner: tx-sender}
            (merge owner-balance {
                available-credits: (- (get available-credits owner-balance) amount),
                retired-credits: (+ (get retired-credits owner-balance) amount),
                last-updated: current-block
            })
        )
        
        ;; Update global retirement stats
        (var-set total-credits-retired (+ (var-get total-credits-retired) amount))
        
        (ok true)
    )
)

;; Authorize a verifier (owner only)
(define-public (authorize-verifier (verifier principal))
    (let (
        (current-block stacks-block-height)
    )
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
        
        (map-set authorized-verifiers-map
            {verifier: verifier}
            {
                is-active: true,
                verification-count: u0,
                authorized-at: current-block
            }
        )
        
        (var-set authorized-verifiers (+ (var-get authorized-verifiers) u1))
        (ok true)
    )
)

;; Read-only Functions

(define-read-only (get-credit-info (credit-id uint))
    (map-get? carbon-credits {credit-id: credit-id})
)

(define-read-only (get-project-info (project-id uint))
    (map-get? carbon-projects {project-id: project-id})
)

(define-read-only (get-balance (owner principal))
    (map-get? credit-balances {owner: owner})
)

(define-read-only (get-total-minted)
    (var-get total-credits-minted)
)

(define-read-only (get-total-retired)
    (var-get total-credits-retired)
)

(define-read-only (get-next-credit-id)
    (var-get next-credit-id)
)

(define-read-only (get-next-project-id)
    (var-get next-project-id)
)

(define-read-only (is-verifier-authorized (verifier principal))
    (match (map-get? authorized-verifiers-map {verifier: verifier})
        verifier-data (get is-active verifier-data)
        false
    )
)

(define-read-only (get-verifier-stats (verifier principal))
    (map-get? authorized-verifiers-map {verifier: verifier})
)

(define-read-only (get-registry-info (registry-name (string-ascii 64)))
    (map-get? verified-registries {registry-name: registry-name})
)

;; Private Functions

(define-private (is-credit-owner (credit-id uint) (address principal))
    (match (map-get? carbon-credits {credit-id: credit-id})
        credit (is-eq (get owner credit) address)
        false
    )
)
