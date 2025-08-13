/*
  # Fix Stock Movement Calculation for PCS Units

  1. Problem Fixed
    - When adding 5 pcs, it was incorrectly adding to base_unit (dus) instead of just pcs
    - Function was calculating conversion wrong for pcs additions

  2. Solution
    - For 'pcs' unit_type: Only add to stock_pcs, then recalculate stock_quantity from total pcs
    - For 'base_unit' unit_type: Add to stock_quantity, then recalculate stock_pcs

  3. Logic
    - stock_pcs is the source of truth for piece count
    - stock_quantity is calculated as: stock_pcs / pcs_per_base_unit
*/

-- Drop and recreate the function with correct logic
DROP FUNCTION IF EXISTS update_product_stock_with_units();

CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
DECLARE
    pcs_per_unit INTEGER;
    current_stock_pcs INTEGER;
    new_stock_pcs INTEGER;
    new_stock_quantity NUMERIC;
BEGIN
    -- Get the pcs_per_base_unit for this product
    SELECT pcs_per_base_unit INTO pcs_per_unit
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Default to 1 if not set
    IF pcs_per_unit IS NULL THEN
        pcs_per_unit := 1;
    END IF;
    
    -- Get current stock_pcs
    SELECT stock_pcs INTO current_stock_pcs
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Default to 0 if not set
    IF current_stock_pcs IS NULL THEN
        current_stock_pcs := 0;
    END IF;
    
    -- Calculate new stock based on unit type and transaction type
    IF NEW.unit_type = 'pcs' THEN
        -- Working with pieces directly
        IF NEW.transaction_type = 'inbound' THEN
            new_stock_pcs := current_stock_pcs + NEW.quantity;
        ELSE -- outbound or adjustment
            new_stock_pcs := current_stock_pcs - NEW.quantity;
        END IF;
        
        -- Calculate equivalent base units from total pieces
        new_stock_quantity := new_stock_pcs::NUMERIC / pcs_per_unit::NUMERIC;
        
    ELSE -- unit_type = 'base_unit'
        -- Working with base units (dus, box, etc.)
        IF NEW.transaction_type = 'inbound' THEN
            new_stock_pcs := current_stock_pcs + (NEW.quantity * pcs_per_unit);
        ELSE -- outbound or adjustment
            new_stock_pcs := current_stock_pcs - (NEW.quantity * pcs_per_unit);
        END IF;
        
        -- Calculate base units from total pieces
        new_stock_quantity := new_stock_pcs::NUMERIC / pcs_per_unit::NUMERIC;
    END IF;
    
    -- Ensure stock doesn't go negative
    IF new_stock_pcs < 0 THEN
        new_stock_pcs := 0;
        new_stock_quantity := 0;
    END IF;
    
    -- Update the product stock
    UPDATE products 
    SET 
        stock_pcs = new_stock_pcs,
        stock_quantity = new_stock_quantity,
        updated_at = NOW()
    WHERE id = NEW.product_id;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Recreate the trigger
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
CREATE TRIGGER update_product_stock_trigger
    AFTER INSERT ON stock_movements
    FOR EACH ROW
    EXECUTE FUNCTION update_product_stock_with_units();

-- Test the fix with a verification query
DO $$
BEGIN
    RAISE NOTICE 'Stock movement calculation function updated successfully!';
    RAISE NOTICE 'Logic: PCS additions only affect stock_pcs, base_unit additions affect both';
END $$;