;; Carbon DAO Core Contract
;; Decentralized Autonomous Organization for Climate Action Fund Management

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-MEMBER (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u103))
(define-constant ERR-ALREADY-VOTED (err u104))
(define-constant ERR-VOTING-ENDED (err u105))
(define-constant ERR-INSUFFICIENT-TOKENS (err u106))
(define-constant ERR-PROPOSAL-NOT-PASSED (err u107))
(define-constant ERR-ALREADY-EXECUTED (err u108))
(define-constant ERR-EXECUTION-FAILED (err u109))
(define-constant ERR-INVALID-PARAMETERS (err u110))
(define-constant VOTING-PERIOD u1440) ;; ~10 days in blocks
(define-constant MIN-PROPOSAL-THRESHOLD u1000) ;; Minimum tokens to create proposal
(define-constant QUORUM-THRESHOLD u20) ;; 20% participation required

;; Data Variables
(define-data-var next-proposal-id uint u1)
(define-data-var total-token-supply uint u0)
(define-data-var treasury-balance uint u0)
(define-data-var member-count uint u0)

;; Data Maps
(define-map members 
    { address: principal }
    { 
        tokens: uint,
        joined-at: uint,
        is-active: bool,
        reputation: uint
    }
)

(define-map proposals
    { proposal-id: uint }
    {
        creator: principal,
        title: (string-ascii 256),
        description: (string-ascii 1024),
        amount-requested: uint,
        recipient: principal,
        votes-for: uint,
        votes-against: uint,
        voting-ends-at: uint,
        executed: bool,
        created-at: uint,
        proposal-type: (string-ascii 64)
    }
)

(define-map votes
    { proposal-id: uint, voter: principal }
    { 
        vote: bool, ;; true = for, false = against
        tokens-voted: uint,
        voted-at: uint
    }
)

(define-map project-funding
    { project-id: uint }
    {
        name: (string-ascii 256),
        description: (string-ascii 1024),
        funding-goal: uint,
        current-funding: uint,
        project-owner: principal,
        verification-status: (string-ascii 32),
        created-at: uint
    }
)

(define-map member-delegations
    { delegator: principal }
    { 
        delegate: principal,
        delegated-tokens: uint,
        delegation-expires: uint
    }
)

;; Public Functions

;; Initialize member with tokens
(define-public (join-dao (initial-tokens uint))
    (let (
        (caller tx-sender)
        (current-block stacks-block-height)
    )
        (asserts! (> initial-tokens u0) ERR-INVALID-AMOUNT)
        (match (map-get? members {address: caller})
            existing-member ERR-NOT-MEMBER ;; Already a member
            (begin
                (map-set members 
                    {address: caller}
                    {
                        tokens: initial-tokens,
                        joined-at: current-block,
                        is-active: true,
                        reputation: u100
                    }
                )
                (var-set total-token-supply (+ (var-get total-token-supply) initial-tokens))
                (var-set member-count (+ (var-get member-count) u1))
                (ok true)
            )
        )
    )
)

;; Create a new proposal
(define-public (create-proposal (title (string-ascii 256)) (description (string-ascii 1024)) 
                               (amount uint) (recipient principal) (proposal-type (string-ascii 64)))
    (let (
        (caller tx-sender)
        (caller-data (unwrap! (map-get? members {address: caller}) ERR-NOT-MEMBER))
        (proposal-id (var-get next-proposal-id))
        (current-block stacks-block-height)
    )
        (asserts! (get is-active caller-data) ERR-NOT-MEMBER)
        (asserts! (>= (get tokens caller-data) MIN-PROPOSAL-THRESHOLD) ERR-INSUFFICIENT-TOKENS)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= amount (var-get treasury-balance)) ERR-INVALID-AMOUNT)
        
        (map-set proposals
            {proposal-id: proposal-id}
            {
                creator: caller,
                title: title,
                description: description,
                amount-requested: amount,
                recipient: recipient,
                votes-for: u0,
                votes-against: u0,
                voting-ends-at: (+ current-block VOTING-PERIOD),
                executed: false,
                created-at: current-block,
                proposal-type: proposal-type
            }
        )
        
        (var-set next-proposal-id (+ proposal-id u1))
        (ok proposal-id)
    )
)

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool) (tokens-to-vote uint))
    (let (
        (caller tx-sender)
        (caller-data (unwrap! (map-get? members {address: caller}) ERR-NOT-MEMBER))
        (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-PROPOSAL-NOT-FOUND))
        (current-block stacks-block-height)
    )
        (asserts! (get is-active caller-data) ERR-NOT-MEMBER)
        (asserts! (>= (get tokens caller-data) tokens-to-vote) ERR-INSUFFICIENT-TOKENS)
        (asserts! (> tokens-to-vote u0) ERR-INVALID-AMOUNT)
        (asserts! (<= current-block (get voting-ends-at proposal)) ERR-VOTING-ENDED)
        
        ;; Check if already voted
        (match (map-get? votes {proposal-id: proposal-id, voter: caller})
            existing-vote ERR-ALREADY-VOTED
            (begin
                ;; Record vote
                (map-set votes
                    {proposal-id: proposal-id, voter: caller}
                    {
                        vote: vote-for,
                        tokens-voted: tokens-to-vote,
                        voted-at: current-block
                    }
                )
                
                ;; Update proposal vote counts
                (if vote-for
                    (map-set proposals
                        {proposal-id: proposal-id}
                        (merge proposal {votes-for: (+ (get votes-for proposal) tokens-to-vote)})
                    )
                    (map-set proposals
                        {proposal-id: proposal-id}
                        (merge proposal {votes-against: (+ (get votes-against proposal) tokens-to-vote)})
                    )
                )
                
                (ok true)
            )
        )
    )
)

;; Execute a passed proposal
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal (unwrap! (map-get? proposals {proposal-id: proposal-id}) ERR-PROPOSAL-NOT-FOUND))
        (current-block stacks-block-height)
        (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
        (total-supply (var-get total-token-supply))
    )
        (asserts! (> current-block (get voting-ends-at proposal)) ERR-VOTING-ENDED)
        (asserts! (not (get executed proposal)) ERR-ALREADY-EXECUTED)
        
        ;; Check quorum (20% of total supply must participate)
        (asserts! (>= (* total-votes u100) (* total-supply QUORUM-THRESHOLD)) ERR-PROPOSAL-NOT-PASSED)
        
        ;; Check if proposal passed (more votes for than against)
        (asserts! (> (get votes-for proposal) (get votes-against proposal)) ERR-PROPOSAL-NOT-PASSED)
        
        ;; Mark as executed
        (map-set proposals
            {proposal-id: proposal-id}
            (merge proposal {executed: true})
        )
        
        ;; Transfer funds from treasury
        (var-set treasury-balance (- (var-get treasury-balance) (get amount-requested proposal)))
        
        (ok true)
    )
)

;; Add funds to treasury
(define-public (add-to-treasury (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (var-set treasury-balance (+ (var-get treasury-balance) amount))
        (ok true)
    )
)

;; Delegate voting power
(define-public (delegate-voting-power (delegate principal) (tokens uint) (duration uint))
    (let (
        (caller tx-sender)
        (caller-data (unwrap! (map-get? members {address: caller}) ERR-NOT-MEMBER))
        (current-block stacks-block-height)
    )
        (asserts! (get is-active caller-data) ERR-NOT-MEMBER)
        (asserts! (>= (get tokens caller-data) tokens) ERR-INSUFFICIENT-TOKENS)
        (asserts! (> tokens u0) ERR-INVALID-AMOUNT)
        (asserts! (> duration u0) ERR-INVALID-PARAMETERS)
        
        (map-set member-delegations
            {delegator: caller}
            {
                delegate: delegate,
                delegated-tokens: tokens,
                delegation-expires: (+ current-block duration)
            }
        )
        
        (ok true)
    )
)

;; Read-only Functions

(define-read-only (get-member-info (address principal))
    (map-get? members {address: address})
)

(define-read-only (get-proposal (proposal-id uint))
    (map-get? proposals {proposal-id: proposal-id})
)

(define-read-only (get-vote (proposal-id uint) (voter principal))
    (map-get? votes {proposal-id: proposal-id, voter: voter})
)

(define-read-only (get-treasury-balance)
    (var-get treasury-balance)
)

(define-read-only (get-total-supply)
    (var-get total-token-supply)
)

(define-read-only (get-member-count)
    (var-get member-count)
)

(define-read-only (get-next-proposal-id)
    (var-get next-proposal-id)
)

(define-read-only (is-proposal-passed (proposal-id uint))
    (match (map-get? proposals {proposal-id: proposal-id})
        proposal
        (let (
            (total-votes (+ (get votes-for proposal) (get votes-against proposal)))
            (total-supply (var-get total-token-supply))
        )
            (and
                (>= (* total-votes u100) (* total-supply QUORUM-THRESHOLD))
                (> (get votes-for proposal) (get votes-against proposal))
                (> stacks-block-height (get voting-ends-at proposal))
            )
        )
        false
    )
)

(define-read-only (get-delegation-info (delegator principal))
    (map-get? member-delegations {delegator: delegator})
)

;; Private Functions

(define-private (is-member (address principal))
    (match (map-get? members {address: address})
        member-data (get is-active member-data)
        false
    )
)
