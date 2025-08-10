/*
  # Add price_per_pcs field to products table

  1. New Columns
    - `price_per_pcs` (numeric) - Price per piece for individual sales
    - `base_unit` (text) - Base unit type (dus, box, pcs, etc.)
    - `pcs_per_base_unit` (integer) - How many pieces per base unit

  2. Data Migration
    - Set default values for existing products
    - Update price_per_pcs based on existing price and conversion

  3. Security
    - No RLS changes needed (inherits from existing table policies)
*/

-- Add the missing columns to products table
DO $$
BEGIN
  -- Add price_per_pcs column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'price_per_pcs'
  ) THEN
    ALTER TABLE products ADD COLUMN price_per_pcs numeric(12,2) DEFAULT 0;
  END IF;

  -- Add base_unit column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'base_unit'
  ) THEN
    ALTER TABLE products ADD COLUMN base_unit text DEFAULT 'pcs';
  END IF;

  -- Add pcs_per_base_unit column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'pcs_per_base_unit'
  ) THEN
    ALTER TABLE products ADD COLUMN pcs_per_base_unit integer DEFAULT 1;
  END IF;
END $$;

-- Update existing products with default values
UPDATE products 
SET 
  price_per_pcs = COALESCE(price_per_pcs, price),
  base_unit = COALESCE(base_unit, 'pcs'),
  pcs_per_base_unit = COALESCE(pcs_per_base_unit, 1)
WHERE price_per_pcs IS NULL OR base_unit IS NULL OR pcs_per_base_unit IS NULL;

-- Add index for better performance
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);