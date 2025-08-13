/*
  # Add Stock Tracking Features

  1. New Columns
    - `products.initial_stock_quantity` - Stock awal dalam base unit
    - `products.initial_stock_pcs` - Stock awal dalam pieces
    - `products.total_stock_added` - Total stock yang sudah ditambah
    - `products.total_stock_reduced` - Total stock yang sudah dikurangi
    - `products.stock_movement_count` - Jumlah pergerakan stock

  2. Updated Tables
    - Enhanced products table with tracking fields
    - Stock movements remain the same but will be used for history

  3. Functions
    - Update stock tracking when stock movements occur
*/

-- Add tracking columns to products table
DO $$
BEGIN
  -- Add initial stock tracking columns
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'initial_stock_quantity'
  ) THEN
    ALTER TABLE products ADD COLUMN initial_stock_quantity INTEGER DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'initial_stock_pcs'
  ) THEN
    ALTER TABLE products ADD COLUMN initial_stock_pcs INTEGER DEFAULT 0;
  END IF;

  -- Add stock movement tracking columns
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'total_stock_added'
  ) THEN
    ALTER TABLE products ADD COLUMN total_stock_added INTEGER DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'total_stock_reduced'
  ) THEN
    ALTER TABLE products ADD COLUMN total_stock_reduced INTEGER DEFAULT 0;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'stock_movement_count'
  ) THEN
    ALTER TABLE products ADD COLUMN stock_movement_count INTEGER DEFAULT 0;
  END IF;
END $$;

-- Update existing products to set initial stock values
UPDATE products 
SET 
  initial_stock_quantity = stock_quantity,
  initial_stock_pcs = stock_pcs
WHERE initial_stock_quantity IS NULL OR initial_stock_pcs IS NULL;

-- Create or replace the stock tracking function
CREATE OR REPLACE FUNCTION update_product_stock_with_tracking()
RETURNS TRIGGER AS $$
DECLARE
    pcs_per_unit INTEGER;
    complete_units INTEGER;
    movement_pcs INTEGER;
BEGIN
    -- Get the pcs_per_base_unit for the product
    SELECT pcs_per_base_unit INTO pcs_per_unit
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Default to 1 if not set
    IF pcs_per_unit IS NULL THEN
        pcs_per_unit := 1;
    END IF;
    
    -- Calculate movement in pieces for tracking
    IF NEW.unit_type = 'base_unit' THEN
        movement_pcs := NEW.quantity * pcs_per_unit;
    ELSE
        movement_pcs := NEW.quantity;
    END IF;
    
    -- Handle different unit types and transaction types
    IF NEW.unit_type = 'base_unit' THEN
        -- Adding/removing via base units (box, dus, etc.)
        IF NEW.transaction_type = 'inbound' THEN
            -- Add stock via base units
            UPDATE products 
            SET 
                stock_quantity = stock_quantity + NEW.quantity,
                stock_pcs = stock_pcs + (NEW.quantity * pcs_per_unit),
                total_stock_added = total_stock_added + movement_pcs,
                stock_movement_count = stock_movement_count + 1,
                updated_at = NOW()
            WHERE id = NEW.product_id;
        ELSE
            -- Remove stock via base units (outbound/adjustment)
            UPDATE products 
            SET 
                stock_quantity = GREATEST(0, stock_quantity - NEW.quantity),
                stock_pcs = GREATEST(0, stock_pcs - (NEW.quantity * pcs_per_unit)),
                total_stock_reduced = total_stock_reduced + movement_pcs,
                stock_movement_count = stock_movement_count + 1,
                updated_at = NOW()
            WHERE id = NEW.product_id;
        END IF;
        
    ELSIF NEW.unit_type = 'pcs' THEN
        -- Adding/removing via pieces
        IF NEW.transaction_type = 'inbound' THEN
            -- Calculate how many complete base units this represents
            complete_units := NEW.quantity / pcs_per_unit;
            
            -- Add stock via pieces
            UPDATE products 
            SET 
                stock_pcs = stock_pcs + NEW.quantity,
                stock_quantity = stock_quantity + complete_units,
                total_stock_added = total_stock_added + movement_pcs,
                stock_movement_count = stock_movement_count + 1,
                updated_at = NOW()
            WHERE id = NEW.product_id;
        ELSE
            -- Remove stock via pieces (outbound/adjustment)
            complete_units := NEW.quantity / pcs_per_unit;
            
            UPDATE products 
            SET 
                stock_pcs = GREATEST(0, stock_pcs - NEW.quantity),
                stock_quantity = GREATEST(0, stock_quantity - complete_units),
                total_stock_reduced = total_stock_reduced + movement_pcs,
                stock_movement_count = stock_movement_count + 1,
                updated_at = NOW()
            WHERE id = NEW.product_id;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop existing triggers and function
DROP TRIGGER IF EXISTS stock_movement_trigger ON stock_movements;
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
DROP FUNCTION IF EXISTS update_product_stock_with_units();

-- Create new trigger with tracking
CREATE TRIGGER stock_movement_trigger
    AFTER INSERT ON stock_movements
    FOR EACH ROW
    EXECUTE FUNCTION update_product_stock_with_tracking();

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_stock_tracking ON products(total_stock_added, total_stock_reduced, stock_movement_count);

-- Verification
SELECT 'Stock tracking features added successfully' as status;