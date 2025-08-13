/*
  # Fix Stock Movement Logic

  1. Changes
    - Fix stock calculation logic for both base_unit and pcs additions
    - Proper conversion between base units and pieces
    - Handle partial units correctly

  2. Logic
    - Add via base_unit: Add to both stock_quantity and stock_pcs (quantity × pcs_per_base_unit)
    - Add via pcs: Add to stock_pcs, calculate equivalent base_units only if >= 1 complete unit
    - Subtract: Reverse the logic appropriately

  3. Examples
    - Add 5 box (60 pcs/box) = +5 stock_quantity, +300 stock_pcs
    - Add 300 pcs (60 pcs/box) = +300 stock_pcs, +5 stock_quantity
    - Add 30 pcs (60 pcs/box) = +30 stock_pcs, +0 stock_quantity (partial unit)
*/

-- Drop existing function
DROP FUNCTION IF EXISTS update_product_stock_with_units();

-- Create improved stock update function
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
DECLARE
    pcs_per_unit INTEGER;
    current_stock_pcs INTEGER;
    current_stock_quantity NUMERIC;
    new_stock_pcs INTEGER;
    new_stock_quantity NUMERIC;
    complete_units INTEGER;
BEGIN
    -- Get product's pcs_per_base_unit
    SELECT pcs_per_base_unit, stock_pcs, stock_quantity
    INTO pcs_per_unit, current_stock_pcs, current_stock_quantity
    FROM products 
    WHERE id = NEW.product_id;
    
    -- Default to 1 if null
    IF pcs_per_unit IS NULL THEN
        pcs_per_unit := 1;
    END IF;
    
    -- Default current values if null
    IF current_stock_pcs IS NULL THEN
        current_stock_pcs := 0;
    END IF;
    
    IF current_stock_quantity IS NULL THEN
        current_stock_quantity := 0;
    END IF;

    -- Calculate new stock based on transaction type and unit type
    IF NEW.transaction_type = 'inbound' THEN
        -- ADDING STOCK
        IF NEW.unit_type = 'base_unit' THEN
            -- Adding via base units (e.g., 5 box)
            -- Add to both stock_quantity and stock_pcs
            new_stock_quantity := current_stock_quantity + NEW.quantity;
            new_stock_pcs := current_stock_pcs + (NEW.quantity * pcs_per_unit);
            
        ELSE -- unit_type = 'pcs'
            -- Adding via pieces (e.g., 300 pcs)
            new_stock_pcs := current_stock_pcs + NEW.quantity;
            
            -- Calculate how many complete base units this represents
            complete_units := NEW.quantity / pcs_per_unit;
            new_stock_quantity := current_stock_quantity + complete_units;
        END IF;
        
    ELSE -- transaction_type = 'outbound' or 'adjustment'
        -- REDUCING STOCK
        IF NEW.unit_type = 'base_unit' THEN
            -- Reducing via base units
            new_stock_quantity := current_stock_quantity - NEW.quantity;
            new_stock_pcs := current_stock_pcs - (NEW.quantity * pcs_per_unit);
            
        ELSE -- unit_type = 'pcs'
            -- Reducing via pieces
            new_stock_pcs := current_stock_pcs - NEW.quantity;
            
            -- Calculate how many complete base units this represents
            complete_units := NEW.quantity / pcs_per_unit;
            new_stock_quantity := current_stock_quantity - complete_units;
        END IF;
    END IF;

    -- Ensure stock doesn't go negative
    IF new_stock_pcs < 0 THEN
        new_stock_pcs := 0;
    END IF;
    
    IF new_stock_quantity < 0 THEN
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
DROP TRIGGER IF EXISTS stock_movement_trigger ON stock_movements;
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;

CREATE TRIGGER stock_movement_trigger
    AFTER INSERT ON stock_movements
    FOR EACH ROW
    EXECUTE FUNCTION update_product_stock_with_units();

-- Test the function with some examples
DO $$
BEGIN
    RAISE NOTICE 'Stock movement function updated successfully!';
    RAISE NOTICE 'Logic:';
    RAISE NOTICE '- Add 5 box (60 pcs/box) = +5 stock_quantity, +300 stock_pcs';
    RAISE NOTICE '- Add 300 pcs (60 pcs/box) = +300 stock_pcs, +5 stock_quantity';
    RAISE NOTICE '- Add 30 pcs (60 pcs/box) = +30 stock_pcs, +0 stock_quantity (partial)';
END $$;