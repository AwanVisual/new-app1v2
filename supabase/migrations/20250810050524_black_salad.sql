/*
  # Add stock_pcs column to products table

  1. New Columns
    - `stock_pcs` (integer) - Stock quantity in pieces for direct PCS transactions
  
  2. Data Migration
    - Calculate initial stock_pcs from existing stock_quantity * pcs_per_base_unit
    - Update all existing products with calculated stock_pcs
  
  3. Triggers
    - Update trigger to maintain both stock_quantity and stock_pcs
    - Ensure data consistency between base unit and pieces
*/

-- Add stock_pcs column to products table
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'stock_pcs'
  ) THEN
    ALTER TABLE products ADD COLUMN stock_pcs integer DEFAULT 0;
  END IF;
END $$;

-- Migrate existing data: calculate stock_pcs from stock_quantity * pcs_per_base_unit
UPDATE products 
SET stock_pcs = FLOOR(stock_quantity * COALESCE(pcs_per_base_unit, 1))
WHERE stock_pcs IS NULL OR stock_pcs = 0;

-- Create or replace the stock update function to handle both stock_quantity and stock_pcs
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
DECLARE
  product_record RECORD;
  stock_change_base_units NUMERIC;
  stock_change_pcs INTEGER;
BEGIN
  -- Get product details
  SELECT stock_quantity, stock_pcs, pcs_per_base_unit, base_unit
  INTO product_record
  FROM products
  WHERE id = NEW.product_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product not found: %', NEW.product_id;
  END IF;

  -- Calculate stock changes based on unit type
  IF NEW.unit_type = 'pcs' THEN
    -- Direct PCS transaction
    stock_change_pcs = NEW.quantity;
    stock_change_base_units = NEW.quantity::NUMERIC / COALESCE(product_record.pcs_per_base_unit, 1);
  ELSE
    -- Base unit transaction
    stock_change_base_units = NEW.quantity;
    stock_change_pcs = NEW.quantity * COALESCE(product_record.pcs_per_base_unit, 1);
  END IF;

  -- Apply stock changes based on transaction type
  IF NEW.transaction_type = 'inbound' THEN
    -- Increase stock
    UPDATE products
    SET 
      stock_quantity = stock_quantity + stock_change_base_units,
      stock_pcs = stock_pcs + stock_change_pcs,
      updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'outbound' THEN
    -- Decrease stock
    UPDATE products
    SET 
      stock_quantity = stock_quantity - stock_change_base_units,
      stock_pcs = stock_pcs - stock_change_pcs,
      updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'adjustment' THEN
    -- Direct adjustment
    UPDATE products
    SET 
      stock_quantity = stock_change_base_units,
      stock_pcs = stock_change_pcs,
      updated_at = now()
    WHERE id = NEW.product_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
CREATE TRIGGER update_product_stock_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock_with_units();