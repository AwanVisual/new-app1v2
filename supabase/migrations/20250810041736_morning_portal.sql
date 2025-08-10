/*
  # Add Simplified Product Units System

  1. Database Changes
    - Add `base_unit` column to products (dropdown: pcs, dus, lusin, etc.)
    - Add `pcs_per_base_unit` column (conversion factor)
    - Add `price_per_pcs` column (separate pricing)
    - Add `unit_type` and `unit_id` to sale_items and stock_movements
    - Update triggers for stock management with units

  2. Features
    - Simple base unit selection (pcs, dus, lusin, kodi, gross, kg, gram, liter, ml, meter, cm)
    - Conversion factor: 1 base_unit = X pcs
    - Dual pricing: price per base_unit and price per pcs
    - Cashier can sell in pcs or base_unit
    - Automatic stock conversion and management

  3. Security
    - Maintain existing RLS policies
    - Add indexes for performance
*/

-- Add new columns to products table
DO $$
BEGIN
  -- Add base_unit column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'base_unit'
  ) THEN
    ALTER TABLE products ADD COLUMN base_unit text DEFAULT 'pcs';
  END IF;

  -- Add pcs_per_base_unit column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'pcs_per_base_unit'
  ) THEN
    ALTER TABLE products ADD COLUMN pcs_per_base_unit integer DEFAULT 1;
  END IF;

  -- Add price_per_pcs column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'price_per_pcs'
  ) THEN
    ALTER TABLE products ADD COLUMN price_per_pcs numeric(12,2) DEFAULT 0;
  END IF;
END $$;

-- Add unit_type and unit_id columns to sale_items
DO $$
BEGIN
  -- Add unit_type column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;

  -- Add unit_id column if not exists (for future expansion)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_id uuid;
  END IF;
END $$;

-- Add unit_type and unit_id columns to stock_movements
DO $$
BEGIN
  -- Add unit_type column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;

  -- Add unit_id column if not exists
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_id uuid;
  END IF;
END $$;

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);

-- Update the stock movement trigger function to handle units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
BEGIN
  -- Convert quantity to pieces based on unit_type
  DECLARE
    quantity_in_pcs integer;
    product_pcs_per_base_unit integer;
  BEGIN
    -- Get the product's pcs_per_base_unit
    SELECT pcs_per_base_unit INTO product_pcs_per_base_unit
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Convert quantity to pieces
    IF NEW.unit_type = 'pcs' THEN
      quantity_in_pcs := NEW.quantity;
    ELSE
      -- For base_unit, multiply by conversion factor
      quantity_in_pcs := NEW.quantity * COALESCE(product_pcs_per_base_unit, 1);
    END IF;
    
    -- Update product stock based on transaction type
    IF NEW.transaction_type = 'inbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity + quantity_in_pcs,
          updated_at = now()
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity - quantity_in_pcs,
          updated_at = now()
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
      UPDATE products 
      SET stock_quantity = quantity_in_pcs,
          updated_at = now()
      WHERE id = NEW.product_id;
    END IF;
    
    RETURN NEW;
  END;
END;
$$ LANGUAGE plpgsql;

-- Drop existing trigger and create new one
DROP TRIGGER IF EXISTS stock_movement_trigger ON stock_movements;
CREATE TRIGGER stock_movement_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock_with_units();

-- Update existing products to have proper default values
UPDATE products 
SET 
  base_unit = COALESCE(base_unit, 'pcs'),
  pcs_per_base_unit = COALESCE(pcs_per_base_unit, 1),
  price_per_pcs = COALESCE(price_per_pcs, price)
WHERE base_unit IS NULL OR pcs_per_base_unit IS NULL OR price_per_pcs IS NULL;