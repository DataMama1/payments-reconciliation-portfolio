# Payments Reconciliation Portfolio

Four projects covering payment settlement, card dispute monitoring, bank-to-book reconciliation, and interbank transfer reconciliation with suspense aging. All data is simulated.

## Projects

| # | Project | Tools | Folder |
|---|---|---|---|
| 1 | Payment Gateway Settlement & Revenue Leakage Reconciliation | PostgreSQL, Excel | [01-gateway-settlement-reconciliation](./01-gateway-settlement-reconciliation) |
| 2 | Payment Integrity & Card Scheme Dispute Monitoring | Power Query, Excel | [02-card-dispute-monitoring](./02-card-dispute-monitoring) |
| 3 | Bank-to-Book Cash Reconciliation | Excel | [03-bank-to-book-reconciliation](./03-bank-to-book-reconciliation) |
| 4 | Interbank Transfer, ATM & POS Settlement Reconciliation with Suspense Aging | PostgreSQL, Excel (Power Query) | [04-interbank-suspense-reconciliation](./04-interbank-suspense-reconciliation) |

## 1. Gateway Settlement Reconciliation
Matches internal e-commerce orders against Paystack-style payout files. Flags duplicate gateway charges, fee overcharges against a contracted rate (1.5% + ₦100, capped at ₦2,000), pending settlements, gross amount mismatches, unannounced chargebacks, and unmatched gateway credits.

## 2. Card Dispute Monitoring
Cleans and merges card transactions with scheme disputes in Power Query, flags velocity and card-testing patterns, and tracks dispute ratio and event count against Visa VAMP (CEMEA tier) and Mastercard ECM thresholds.

## 3. Bank-to-Book Reconciliation
Matches ledger entries to bank statement lines, classifies each exception (timing difference, pending settlement, amount mismatch, unrecorded bank charge), and proves the ledger and bank balances tie out.

## 4. Interbank Transfer, ATM & POS Settlement Reconciliation with Suspense Aging
Three-way reconciliation of core banking records, switch settlement reports, and the suspense GL, joined on the switch reference. 

## Repository structure
```
├── README.md
├── 01-gateway-settlement-reconciliation/
├── 02-card-dispute-monitoring/
├── 03-bank-to-book-reconciliation/
└── 04-interbank-suspense-reconciliation/
    ├── data/            (core_banking_txns.csv, switch_settlement_report.csv, suspense_gl.csv)
    ├── sql/             (schema, quality checks, reconciliation, reversal monitoring, aging, exception register)
    ├── dashboard/       (Excel workbook, dashboard screenshot)
    ├── data_generator/  (script used to simulate the three files)
    └── README.md        (project-level documentation)
```

## Contact
Lateefat Oyebola · [[LinkedIn](https://www.linkedin.com/in/lateefatoyerinde/)]] · meetlateefaah@gmail.com

