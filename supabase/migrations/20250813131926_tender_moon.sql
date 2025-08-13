/*
  # Add unit_type and discount configuration columns

  1. New Columns
    - `sale_items` table:
      - `unit_type` (text) - stores 'pcs' or 'base_unit'
      - `unit_id` (uuid) - reference to product_units table (for future use)
    - `stock_movements` table:
      - `unit_type` (text) - stores 'pcs' or 'base_unit' 
      - `unit_id` (uuid) - reference to product_units table (for future use)

  2. Indexes
    - Add indexes for better query performance on unit_type columns

  3. Default Values
    - Set default unit_type to 'base_unit' for existing records
*/

-- Add unit_type and unit_id columns to sale_items table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_id uuid;
  END IF;
END $$;

-- Add unit_type and unit_id columns to stock_movements table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_id uuid;
  END IF;
END $$;

-- Create product_units table if it doesn't exist
CREATE TABLE IF NOT EXISTS product_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  unit_name text NOT NULL,
  conversion_factor numeric(12,4) DEFAULT 1 NOT NULL,
  is_base_unit boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES users(id),
  UNIQUE(product_id, unit_name)
);

-- Enable RLS on product_units table
ALTER TABLE product_units ENABLE ROW LEVEL SECURITY;

-- Add RLS policies for product_units
CREATE POLICY "Admins and stockists can manage product units"
  ON product_units
  FOR ALL
  TO public
  USING (get_user_role(uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

CREATE POLICY "All authenticated users can view product units"
  ON product_units
  FOR SELECT
  TO authenticated
  USING (true);

-- Add foreign key constraints for unit_id columns
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'sale_items_unit_id_fkey'
  ) THEN
    ALTER TABLE sale_items ADD CONSTRAINT sale_items_unit_id_fkey 
    FOREIGN KEY (unit_id) REFERENCES product_units(id);
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'stock_movements_unit_id_fkey'
  ) THEN
    ALTER TABLE stock_movements ADD CONSTRAINT stock_movements_unit_id_fkey 
    FOREIGN KEY (unit_id) REFERENCES product_units(id);
  END IF;
END $$;

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);

-- Add indexes for discount column
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);