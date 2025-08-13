/*
  # Fix Stock Movement Unit Calculation

  1. Problem Fixed
    - When adding stock in 'pcs', the system was incorrectly adding to base_unit instead of pieces
    - The conversion logic was backwards in the trigger function

  2. Solution
    - Fixed the unit conversion logic in update_product_stock_with_units() function
    - Now correctly handles both 'pcs' and 'base_unit' stock movements
    - Proper calculation for stock_quantity and stock_pcs fields

  3. Logic
    - When unit_type = 'pcs': Add directly to stock_pcs, calculate base units
    - When unit_type = 'base_unit': Add to stock_quantity, calculate total pcs
*/

-- Drop and recreate the function with correct logic
DROP FUNCTION IF EXISTS update_product_stock_with_units();

CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
DECLARE
    pcs_per_base_unit_val INTEGER;
    quantity_to_add_pcs INTEGER;
    quantity_to_add_base_units NUMERIC;
BEGIN
    -- Get the pcs_per_base_unit for this product
    SELECT pcs_per_base_unit INTO pcs_per_base_unit_val
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Default to 1 if not set
    IF pcs_per_base_unit_val IS NULL THEN
        pcs_per_base_unit_val := 1;
    END IF;
    
    -- Calculate quantities based on unit_type and transaction_type
    IF NEW.unit_type = 'pcs' THEN
        -- Adding/removing pieces directly
        IF NEW.transaction_type = 'inbound' THEN
            quantity_to_add_pcs := NEW.quantity;
        ELSE
            quantity_to_add_pcs := -NEW.quantity;
        END IF;
        
        -- Calculate equivalent base units
        quantity_to_add_base_units := quantity_to_add_pcs::NUMERIC / pcs_per_base_unit_val;
        
    ELSE -- unit_type = 'base_unit'
        -- Adding/removing base units
        IF NEW.transaction_type = 'inbound' THEN
            quantity_to_add_base_units := NEW.quantity;
            quantity_to_add_pcs := NEW.quantity * pcs_per_base_unit_val;
        ELSE
            quantity_to_add_base_units := -NEW.quantity;
            quantity_to_add_pcs := -NEW.quantity * pcs_per_base_unit_val;
        END IF;
    END IF;
    
    -- Update the product stock
    UPDATE products 
    SET 
        stock_quantity = GREATEST(0, stock_quantity + quantity_to_add_base_units),
        stock_pcs = GREATEST(0, COALESCE(stock_pcs, 0) + quantity_to_add_pcs),
        updated_at = NOW()
    WHERE id = NEW.product_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;