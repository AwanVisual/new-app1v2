/*
  # Create Sale Items Table

  1. New Tables
    - `sale_items`
      - `id` (uuid, primary key)
      - `sale_id` (uuid, references sales, cascade delete)
      - `product_id` (uuid, references products)
      - `quantity` (integer, required)
      - `unit_price` (numeric, required)
      - `subtotal` (numeric, required)
      - `discount` (numeric, default 0)
      - `created_at` (timestamp)

  2. Security
    - Enable RLS on `sale_items` table
    - Users can view sale items
    - Users can create sale items
    - Admins can manage sale items

  3. Indexes
    - Index on discount for filtering discounted items
*/

CREATE TABLE IF NOT EXISTS sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid REFERENCES sales(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  quantity integer NOT NULL,
  unit_price numeric(12,2) NOT NULL,
  subtotal numeric(12,2) NOT NULL,
  discount numeric(10,2) DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;

-- Create index for discount filtering
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);

-- Policies for sale_items
CREATE POLICY "Users can view sale items"
  ON sale_items
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can create sale items"
  ON sale_items
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Admins can manage sale items"
  ON sale_items
  FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin');