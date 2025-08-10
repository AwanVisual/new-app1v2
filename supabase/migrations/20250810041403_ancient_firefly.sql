/*
  # Simplified Product Units System

  1. Database Changes
    - Add base_unit dropdown options to products table
    - Add pcs_per_base_unit for conversion
    - Add price_per_pcs for pricing flexibility
    - Update triggers for stock calculations

  2. New Columns
    - `base_unit` (text): Selected unit type (pcs, dus, lusin, etc.)
    - `pcs_per_base_unit` (integer): How many pieces per base unit
    - `price_per_pcs` (numeric): Price per piece for flexible pricing

  3. Stock Management
    - All stock stored in pieces (pcs) internally
    - Display and input based on selected base unit
    - Automatic conversion between units
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

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);

-- Update existing products to have proper price_per_pcs
UPDATE products 
SET price_per_pcs = price / GREATEST(pcs_per_base_unit, 1)
WHERE price_per_pcs = 0 OR price_per_pcs IS NULL;

-- Add unit_id and unit_type to sale_items if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_id uuid REFERENCES product_units(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;
END $$;

-- Add unit_id and unit_type to stock_movements if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_id'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_id uuid REFERENCES product_units(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;
END $$;

-- Add indexes for sale_items
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);

-- Add indexes for stock_movements
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);

-- Create or replace function to update product stock with units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
BEGIN
  -- Calculate quantity in pieces (pcs)
  DECLARE
    quantity_in_pcs integer;
    product_pcs_per_unit integer;
  BEGIN
    -- Get the product's pcs_per_base_unit
    SELECT pcs_per_base_unit INTO product_pcs_per_unit
    FROM products 
    WHERE id = NEW.product_id;
    
    -- If unit_type is 'base_unit', use the product's conversion
    -- If unit_type is 'pcs', quantity is already in pieces
    IF NEW.unit_type = 'pcs' THEN
      quantity_in_pcs := NEW.quantity;
    ELSE
      -- Use product's base unit conversion
      quantity_in_pcs := NEW.quantity * COALESCE(product_pcs_per_unit, 1);
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

-- Create trigger for stock movements
DROP TRIGGER IF EXISTS stock_movement_trigger ON stock_movements;
CREATE TRIGGER stock_movement_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock_with_units();