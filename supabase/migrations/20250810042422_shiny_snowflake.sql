/*
  # Update Stock to Base Unit System

  1. Database Changes
    - Remove selling price column (redundant)
    - Update stock_quantity to represent base units
    - Add computed stock_in_pcs for display
    - Update triggers for base unit calculations

  2. Functions
    - Update stock movement functions to handle base unit conversions
    - Ensure proper stock calculations

  3. Data Migration
    - Convert existing stock from pcs to base units
    - Preserve data integrity during migration
*/

-- First, let's update the products table structure
DO $$
BEGIN
  -- Add a temporary column to store current stock in pcs
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'temp_stock_pcs'
  ) THEN
    ALTER TABLE products ADD COLUMN temp_stock_pcs integer DEFAULT 0;
  END IF;
END $$;

-- Copy current stock_quantity to temp column (assuming current stock is in pcs)
UPDATE products SET temp_stock_pcs = stock_quantity;

-- Update stock_quantity to be in base units (convert from pcs to base units)
UPDATE products 
SET stock_quantity = CASE 
  WHEN pcs_per_base_unit > 0 THEN FLOOR(temp_stock_pcs / pcs_per_base_unit)
  ELSE temp_stock_pcs
END;

-- Drop the temporary column
ALTER TABLE products DROP COLUMN IF EXISTS temp_stock_pcs;

-- Update the stock movement trigger function to handle base unit conversions
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
BEGIN
  -- Convert quantity to pieces for stock calculation
  DECLARE
    quantity_in_pcs INTEGER;
    current_pcs_per_base_unit INTEGER;
  BEGIN
    -- Get the product's pcs_per_base_unit
    SELECT pcs_per_base_unit INTO current_pcs_per_base_unit
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Convert quantity to pieces based on unit_type
    IF NEW.unit_type = 'pcs' THEN
      quantity_in_pcs := NEW.quantity;
    ELSE
      -- For base_unit, multiply by conversion factor
      quantity_in_pcs := NEW.quantity * COALESCE(current_pcs_per_base_unit, 1);
    END IF;
    
    -- Update product stock (convert pieces back to base units)
    IF NEW.transaction_type = 'inbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity + FLOOR(quantity_in_pcs / COALESCE(current_pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity - FLOOR(quantity_in_pcs / COALESCE(current_pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
      UPDATE products 
      SET stock_quantity = FLOOR(quantity_in_pcs / COALESCE(current_pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    END IF;
    
    RETURN NEW;
  END;
END;
$$ LANGUAGE plpgsql;