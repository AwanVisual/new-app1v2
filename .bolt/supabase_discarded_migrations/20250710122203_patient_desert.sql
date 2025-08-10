/*
  # Create Sales Table

  1. New Tables
    - `sales`
      - `id` (uuid, primary key)
      - `sale_number` (text, unique, required)
      - `customer_name` (text, optional)
      - `subtotal` (numeric, required)
      - `tax_amount` (numeric, default 0)
      - `total_amount` (numeric, required)
      - `payment_method` (payment_method, required)
      - `payment_received` (numeric, required)
      - `change_amount` (numeric, default 0)
      - `notes` (text, optional)
      - `created_at` (timestamp)
      - `created_by` (uuid, references auth.users)
      - `cashier_id` (uuid, references profiles)
      - `invoice_status` (invoice_status, default 'lunas')

  2. Security
    - Enable RLS on `sales` table
    - All authenticated users can view sales
    - All authenticated users can create sales (with created_by check)
    - Admins can manage all sales

  3. Indexes
    - Index on cashier_id for performance
    - Index on invoice_status for filtering
*/

CREATE TABLE IF NOT EXISTS sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_number text UNIQUE NOT NULL,
  customer_name text,
  subtotal numeric(12,2) NOT NULL,
  tax_amount numeric(12,2) NOT NULL DEFAULT 0,
  total_amount numeric(12,2) NOT NULL,
  payment_method payment_method NOT NULL,
  payment_received numeric(12,2) NOT NULL,
  change_amount numeric(12,2) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  cashier_id uuid REFERENCES profiles(id),
  invoice_status invoice_status DEFAULT 'lunas'::invoice_status
);

ALTER TABLE sales ENABLE ROW LEVEL SECURITY;

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice_status ON sales(invoice_status);

-- Policies for sales
CREATE POLICY "All authenticated users can view sales"
  ON sales
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create sales"
  ON sales
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins can manage all sales"
  ON sales
  FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin');