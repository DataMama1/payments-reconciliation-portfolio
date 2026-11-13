# Payments Reconciliation Portfolio

Three projects covering payment settlement, card dispute monitoring, and bank-to-book reconciliation. All data is simulated.

**Portfolio page:** [add Notion link]

## Projects

| # | Project | Tools | Folder |
|---|---|---|---|
| 1 | Payment Gateway Settlement & Revenue Leakage Reconciliation | PostgreSQL, Excel | [01-gateway-settlement-reconciliation](./01-gateway-settlement-reconciliation) |
| 2 | Payment Integrity & Card Scheme Dispute Monitoring | Power Query, Excel | [02-card-dispute-monitoring](./02-card-dispute-monitoring) |
| 3 | Bank-to-Book Cash Reconciliation | Excel | [03-bank-to-book-reconciliation](./03-bank-to-book-reconciliation) |

## 1. Gateway Settlement Reconciliation
Matches internal e-commerce orders against Paystack-style payout files. Flags duplicate gateway charges, fee overcharges against a contracted rate (1.5% + ₦100, capped at ₦2,000), pending settlements, gross amount mismatches, unannounced chargebacks, and unmatched gateway credits.

## 2. Card Dispute Monitoring
Cleans and merges card transactions with scheme disputes in Power Query, flags velocity and card-testing patterns, and tracks dispute ratio and event count against Visa VAMP (CEMEA tier) and Mastercard ECM thresholds.

## 3. Bank-to-Book Reconciliation
Matches ledger entries to bank statement lines, classifies each exception (timing difference, pending settlement, amount mismatch, unrecorded bank charge), and proves the ledger and bank balances tie out.

## Data and assumptions
- All datasets are simulated. No real customer, company, or bank data is used.
- The ₦4,000 dispute fee, fee rates, and fraud rules are modeled assumptions.
- Project 2 is a simplified model: dispute ratio is disputes divided by total transactions. Visa VAMP also counts fraud reports (TC40) and uses settled card-not-present transactions. Thresholds should be checked against Visa and Mastercard's current published rules.

## Repository structure
```
├── README.md
├── 01-gateway-settlement-reconciliation/
├── 02-card-dispute-monitoring/
└── 03-bank-to-book-reconciliation/
```

## Contact
[Your name] · [LinkedIn] · [Email]
