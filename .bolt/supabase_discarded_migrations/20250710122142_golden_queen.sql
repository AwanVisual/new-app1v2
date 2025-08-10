/*
  # Create Enums

  1. Enums
    - `user_role` - admin, cashier, stockist
    - `payment_method` - cash, card, transfer, credit
    - `transaction_type` - inbound, outbound, adjustment
    - `invoice_status` - lunas, dp, belum_bayar

  2. Security
    - These are foundational enums used throughout the application
*/

-- Create user role enum
CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');

-- Create payment method enum
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');

-- Create transaction type enum
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');

-- Create invoice status enum
CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');