/*
  # Fix Stock Trigger for PCS Conversion

  1. Database Changes
    - Update trigger function to handle unit conversion properly
    - Convert PCS purchases to base unit equivalent
    - Maintain stock_quantity in base units only

  2. Logic
    - When buying PCS: convert to base unit fraction
    - When buying base unit: use quantity directly
    - Update stock_quantity field correctly

  3. Example
    - Stock: 120 dus (1440 pcs total)
    - Buy 15 pcs: 15/12 = 1.25 dus reduction
    - New stock: 120 - 1.25 = 118.75 dus
*/

-- Drop existing trigger and function
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
DROP FUNCTION IF EXISTS update_product_stock_with_units();

-- Create improved function that handles unit conversion
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
DECLARE
    stock_change_in_base_units NUMERIC;
    product_pcs_per_base_unit INTEGER;
BEGIN
    -- Get the product's conversion factor
    SELECT pcs_per_base_unit INTO product_pcs_per_base_unit
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Default to 1 if not set
    IF product_pcs_per_base_unit IS NULL THEN
        product_pcs_per_base_unit := 1;
    END IF;
    
    -- Calculate stock change in base units
    IF NEW.unit_type = 'pcs' THEN
        -- Convert PCS to base units: quantity_pcs / pcs_per_base_unit
        stock_change_in_base_units := NEW.quantity::NUMERIC / product_pcs_per_base_unit::NUMERIC;
    ELSE
        -- Already in base units
        stock_change_in_base_units := NEW.quantity::NUMERIC;
    END IF;
    
    -- Update product stock based on transaction type
    IF NEW.transaction_type = 'inbound' THEN
        -- Add to stock
        UPDATE products 
        SET stock_quantity = stock_quantity + stock_change_in_base_units
        WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
        -- Subtract from stock
        UPDATE products 
        SET stock_quantity = stock_quantity - stock_change_in_base_units
        WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
        -- Direct adjustment
        UPDATE products 
        SET stock_quantity = stock_change_in_base_units
        WHERE id = NEW.product_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
CREATE TRIGGER update_product_stock_trigger
    AFTER INSERT ON stock_movements
    FOR EACH ROW
    EXECUTE FUNCTION update_product_stock_with_units();