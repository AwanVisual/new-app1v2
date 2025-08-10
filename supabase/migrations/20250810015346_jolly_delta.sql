/*
  # Simplified Product Units System

  1. Database Changes
    - Add base_unit column to products table
    - Add pcs_per_base_unit column for conversion
    - Add price_per_pcs column for flexible pricing
    - Update sale_items to track unit used
    - Update stock_movements for proper tracking

  2. Features
    - Automatic conversion between base unit and pcs
    - Dual pricing system (base unit price + pcs price)
    - Simple dropdown for base unit selection
    - Automatic calculation in cashier

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

-- Add unit_type column to sale_items to track which unit was used
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE sale_items ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;
END $$;

-- Add unit_type column to stock_movements
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'stock_movements' AND column_name = 'unit_type'
  ) THEN
    ALTER TABLE stock_movements ADD COLUMN unit_type text DEFAULT 'base_unit';
  END IF;
END $$;

-- Create function to update product stock with unit conversion
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
BEGIN
  -- Convert quantity to base units for stock calculation
  DECLARE
    base_quantity integer;
    product_pcs_per_base integer;
  BEGIN
    -- Get the product's pcs_per_base_unit
    SELECT pcs_per_base_unit INTO product_pcs_per_base
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Calculate base quantity based on unit type
    IF NEW.unit_type = 'pcs' THEN
      -- Convert pcs to base units
      base_quantity := CEIL(NEW.quantity::numeric / product_pcs_per_base);
    ELSE
      -- Already in base units
      base_quantity := NEW.quantity;
    END IF;
    
    -- Update product stock based on transaction type
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
END;
$$ LANGUAGE plpgsql;

-- Update the trigger to use the new function
DROP TRIGGER IF EXISTS stock_movement_trigger ON stock_movements;
CREATE TRIGGER stock_movement_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock_with_units();

-- Add indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);

-- Update existing products to have proper default values
UPDATE products 
SET 
  base_unit = COALESCE(base_unit, 'pcs'),
  pcs_per_base_unit = COALESCE(pcs_per_base_unit, 1),
  price_per_pcs = CASE 
    WHEN price_per_pcs = 0 OR price_per_pcs IS NULL 
    THEN price / COALESCE(pcs_per_base_unit, 1)
    ELSE price_per_pcs 
  END
WHERE base_unit IS NULL OR pcs_per_base_unit IS NULL OR price_per_pcs = 0;