/*
  # Add Product Units System

  1. New Tables
    - `product_units`
      - `id` (uuid, primary key)
      - `product_id` (uuid, foreign key to products)
      - `unit_name` (text, e.g., 'pcs', 'dus', 'box')
      - `conversion_factor` (numeric, conversion to base unit)
      - `is_base_unit` (boolean, marks the base unit)
      - `is_active` (boolean)
      - `created_at` (timestamp)

  2. Modifications to existing tables
    - Add `base_unit` column to products table
    - Add `unit_id` column to sale_items table
    - Add `unit_id` column to stock_movements table

  3. Functions
    - Function to convert between units
    - Function to get available units for a product

  4. Security
    - Enable RLS on product_units table
    - Add policies for CRUD operations
*/

-- Create product_units table
CREATE TABLE IF NOT EXISTS product_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  unit_name text NOT NULL,
  conversion_factor numeric(12,4) NOT NULL DEFAULT 1,
  is_base_unit boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  UNIQUE(product_id, unit_name)
);

-- Add base_unit column to products table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'base_unit'
  ) THEN
    ALTER TABLE products ADD COLUMN base_unit text DEFAULT 'pcs';
  END IF;
END $$;

-- Add unit_id column to sale_items table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_id uuid REFERENCES product_units(id);
  END IF;
END $$;

-- Add unit_id column to stock_movements table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_id uuid REFERENCES product_units(id);
  END IF;
END $$;

-- Enable RLS on product_units table
ALTER TABLE product_units ENABLE ROW LEVEL SECURITY;

-- Policies for product_units
CREATE POLICY "All authenticated users can view product units"
  ON product_units
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage product units"
  ON product_units
  FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Function to convert quantity between units
CREATE OR REPLACE FUNCTION convert_quantity(
  p_product_id uuid,
  p_from_unit_id uuid,
  p_to_unit_id uuid,
  p_quantity numeric
) RETURNS numeric AS $$
DECLARE
  from_factor numeric;
  to_factor numeric;
  result numeric;
BEGIN
  -- Get conversion factors
  SELECT conversion_factor INTO from_factor
  FROM product_units
  WHERE id = p_from_unit_id AND product_id = p_product_id;
  
  SELECT conversion_factor INTO to_factor
  FROM product_units
  WHERE id = p_to_unit_id AND product_id = p_product_id;
  
  -- If either unit not found, return original quantity
  IF from_factor IS NULL OR to_factor IS NULL THEN
    RETURN p_quantity;
  END IF;
  
  -- Convert: quantity * from_factor / to_factor
  result := p_quantity * from_factor / to_factor;
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to get base unit quantity
CREATE OR REPLACE FUNCTION get_base_unit_quantity(
  p_product_id uuid,
  p_unit_id uuid,
  p_quantity numeric
) RETURNS numeric AS $$
DECLARE
  base_unit_id uuid;
  result numeric;
BEGIN
  -- Get base unit ID
  SELECT id INTO base_unit_id
  FROM product_units
  WHERE product_id = p_product_id AND is_base_unit = true
  LIMIT 1;
  
  -- If no base unit found, return original quantity
  IF base_unit_id IS NULL THEN
    RETURN p_quantity;
  END IF;
  
  -- Convert to base unit
  result := convert_quantity(p_product_id, p_unit_id, base_unit_id, p_quantity);
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Update the stock movement trigger to handle unit conversions
CREATE OR REPLACE FUNCTION update_product_stock()
RETURNS TRIGGER AS $$
DECLARE
  base_quantity numeric;
BEGIN
  -- Convert quantity to base unit
  base_quantity := get_base_unit_quantity(NEW.product_id, NEW.unit_id, NEW.quantity);
  
  -- Update stock based on transaction type
  IF NEW.transaction_type = 'inbound' THEN
    UPDATE products 
    SET stock_quantity = stock_quantity + base_quantity
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'outbound' THEN
    UPDATE products 
    SET stock_quantity = stock_quantity - base_quantity
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'adjustment' THEN
    UPDATE products 
    SET stock_quantity = base_quantity
    WHERE id = NEW.product_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);

-- Insert default units for existing products
INSERT INTO product_units (product_id, unit_name, conversion_factor, is_base_unit, created_by)
SELECT 
  id as product_id,
  COALESCE(base_unit, 'pcs') as unit_name,
  1 as conversion_factor,
  true as is_base_unit,
  created_by
FROM products
WHERE id NOT IN (SELECT DISTINCT product_id FROM product_units WHERE product_id IS NOT NULL);