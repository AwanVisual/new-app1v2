/*
  # Fix Stock Update Trigger for Unit Conversion

  1. Database Functions
    - Update `update_product_stock_with_units` function to handle unit conversions correctly
    - Ensure stock decreases properly for both pcs and base unit purchases

  2. Trigger Updates
    - Fix stock movement calculations
    - Handle unit_type properly (pcs vs base_unit)
    - Convert quantities correctly before updating product stock
*/

-- Drop existing trigger and function
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
DROP FUNCTION IF EXISTS update_product_stock_with_units();

-- Create improved function to handle stock updates with unit conversion
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
DECLARE
    product_record RECORD;
    stock_change_in_base_units NUMERIC;
BEGIN
    -- Get product details
    SELECT * INTO product_record 
    FROM products 
    WHERE id = NEW.product_id;
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Product not found: %', NEW.product_id;
    END IF;
    
    -- Calculate stock change in base units
    IF NEW.unit_type = 'pcs' THEN
        -- Convert pcs to base units
        stock_change_in_base_units = NEW.quantity::NUMERIC / COALESCE(product_record.pcs_per_base_unit, 1);
    ELSE
        -- Already in base units
        stock_change_in_base_units = NEW.quantity;
    END IF;
    
    -- Update product stock based on transaction type
    IF NEW.transaction_type = 'inbound' THEN
        -- Add to stock
        UPDATE products 
        SET stock_quantity = stock_quantity + stock_change_in_base_units,
            updated_at = NOW()
        WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
        -- Subtract from stock
        UPDATE products 
        SET stock_quantity = stock_quantity - stock_change_in_base_units,
            updated_at = NOW()
        WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
        -- Direct adjustment
        UPDATE products 
        SET stock_quantity = NEW.quantity,
            updated_at = NOW()
        WHERE id = NEW.product_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
CREATE TRIGGER update_product_stock_trigger
    AFTER INSERT ON stock_movements
    FOR EACH ROW
    EXECUTE FUNCTION update_product_stock_with_units();