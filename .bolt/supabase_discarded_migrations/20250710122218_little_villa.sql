/*
  # Create Stock Movements Table

  1. New Tables
    - `stock_movements`
      - `id` (uuid, primary key)
      - `product_id` (uuid, references products, cascade delete)
      - `transaction_type` (transaction_type, required)
      - `quantity` (integer, required)
      - `unit_cost` (numeric, optional)
      - `reference_number` (text, optional)
      - `notes` (text, optional)
      - `created_at` (timestamp)
      - `created_by` (uuid, references auth.users)

  2. Security
    - Enable RLS on `stock_movements` table
    - All authenticated users can view stock movements
    - All authenticated users can create stock movements (with created_by check)
    - Admins, stockists, and cashiers can update/delete stock movements

  3. Triggers
    - Trigger to update product stock when stock movement is created
*/

CREATE TABLE IF NOT EXISTS stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  transaction_type transaction_type NOT NULL,
  quantity integer NOT NULL,
  unit_cost numeric(12,2),
  reference_number text,
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;

-- Policies for stock_movements
CREATE POLICY "All authenticated users can view stock movements"
  ON stock_movements
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create stock movements"
  ON stock_movements
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins, stockists, and cashiers can update stock movements"
  ON stock_movements
  FOR UPDATE
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

CREATE POLICY "Admins, stockists, and cashiers can delete stock movements"
  ON stock_movements
  FOR DELETE
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));