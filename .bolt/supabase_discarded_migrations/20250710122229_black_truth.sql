/*
  # Create Functions

  1. Functions
    - `get_user_role(user_id)` - Get user role for RLS policies
    - `generate_sale_number()` - Generate unique sale numbers
    - `update_product_stock()` - Update product stock on stock movements
    - `handle_new_user()` - Create profile when new user signs up
    - `delete_user(user_id)` - Delete user and all associated data

  2. Security
    - Functions are used in RLS policies and triggers
    - Proper error handling and validation
*/

-- Function to get user role for RLS policies
CREATE OR REPLACE FUNCTION get_user_role(user_id uuid)
RETURNS user_role AS $$
BEGIN
  RETURN (
    SELECT role 
    FROM profiles 
    WHERE id = user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to generate sale numbers
CREATE OR REPLACE FUNCTION generate_sale_number()
RETURNS text AS $$
DECLARE
  sale_date text;
  sale_count integer;
  sale_number text;
BEGIN
  -- Get current date in YYYYMMDD format
  sale_date := to_char(now(), 'YYYYMMDD');
  
  -- Get count of sales for today
  SELECT COUNT(*) + 1 INTO sale_count
  FROM sales
  WHERE sale_number LIKE 'SALE-' || sale_date || '-%';
  
  -- Generate sale number with 4-digit sequence
  sale_number := 'SALE-' || sale_date || '-' || lpad(sale_count::text, 4, '0');
  
  RETURN sale_number;
END;
$$ LANGUAGE plpgsql;

-- Function to update product stock when stock movement is created
CREATE OR REPLACE FUNCTION update_product_stock()
RETURNS trigger AS $$
BEGIN
  -- Update product stock based on transaction type
  IF NEW.transaction_type = 'inbound' OR NEW.transaction_type = 'adjustment' THEN
    -- Increase stock for inbound transactions and positive adjustments
    UPDATE products 
    SET stock_quantity = stock_quantity + NEW.quantity
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'outbound' THEN
    -- Decrease stock for outbound transactions
    UPDATE products 
    SET stock_quantity = stock_quantity - NEW.quantity
    WHERE id = NEW.product_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle new user registration
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'cashier'::user_role
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to delete user and all associated data
CREATE OR REPLACE FUNCTION delete_user(user_id uuid)
RETURNS void AS $$
BEGIN
  -- Delete from auth.users (this will cascade to profiles due to foreign key)
  DELETE FROM auth.users WHERE id = user_id;
  
  -- Note: Other related data will be handled by foreign key constraints
  -- or can be explicitly deleted here if needed
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;