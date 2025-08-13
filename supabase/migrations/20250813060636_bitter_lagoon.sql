/*
  # Update existing products initial stock

  1. Purpose
     - Set current stock as initial stock for all existing products
     - Fix products that were created before the initial stock tracking feature
     - Ensure all products have proper initial stock values

  2. Changes
     - Update initial_stock_quantity = current stock_quantity
     - Update initial_stock_pcs = current stock_pcs
     - Only update products where initial stock is 0 or null

  3. Safety
     - Only updates products with missing initial stock data
     - Preserves existing initial stock if already set
     - Uses safe UPDATE with WHERE conditions
*/

-- Update existing products to set current stock as initial stock
-- Only update products where initial stock is not set (0 or null)
UPDATE products 
SET 
  initial_stock_quantity = stock_quantity,
  initial_stock_pcs = COALESCE(stock_pcs, 0)
WHERE 
  (initial_stock_quantity = 0 OR initial_stock_quantity IS NULL)
  AND stock_quantity > 0;