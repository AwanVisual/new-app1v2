/*
  # Fix Stock Movement Trigger for Unit-based Transactions

  1. Updates
    - Update stock movement trigger function to handle unit-based transactions
    - Properly convert units to base units for stock updates
    - Handle both pcs and base_unit transactions correctly

  2. Security
    - Maintain existing RLS policies
    - Ensure proper stock calculations
*/

-- Drop existing trigger and function
DROP TRIGGER IF EXISTS stock_movement_trigger ON stock_movements;
DROP FUNCTION IF EXISTS update_product_stock_with_units();

-- Create updated function to handle unit-based stock movements
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS TRIGGER AS $$
BEGIN
  -- Update product stock based on unit type
  IF NEW.unit_type = 'pcs' THEN
    -- For pcs transactions, convert to base units
    IF NEW.transaction_type = 'inbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity + (NEW.quantity::numeric / COALESCE(pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity - (NEW.quantity::numeric / COALESCE(pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
      UPDATE products 
      SET stock_quantity = NEW.quantity::numeric / COALESCE(pcs_per_base_unit, 1)
      WHERE id = NEW.product_id;
    END IF;
  ELSE
    -- For base_unit transactions, use quantity directly
    IF NEW.transaction_type = 'inbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity + NEW.quantity
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity - NEW.quantity
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'adjustment' THEN
      UPDATE products 
      SET stock_quantity = NEW.quantity
      WHERE id = NEW.product_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;