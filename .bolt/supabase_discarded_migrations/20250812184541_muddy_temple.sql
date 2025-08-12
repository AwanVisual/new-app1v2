/*
  # Complete POS Database Setup - Fixed User Creation
  
  This SQL file creates a complete Point of Sale (POS) database with:
  1. All required tables with proper relationships
  2. Row Level Security (RLS) policies
  3. Authentication setup with auto-profile creation
  4. Storage for file uploads
  5. Sample data for testing
  6. Fixed user creation process
  
  Run this entire file in Supabase SQL Editor to set up the complete database.
*/

-- =====================================================
-- 1. ENUMS DEFINITION
-- =====================================================

DO $$ BEGIN
  CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
  CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');
EXCEPTION
  WHEN duplicate_object THEN null;
END $$;

-- =====================================================
-- 2. CORE TABLES
-- =====================================================

-- Users table (extends auth.users)
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Profiles table
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role user_role DEFAULT 'cashier'::user_role NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Categories table
CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

-- Products table
CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  sku text UNIQUE NOT NULL,
  category_id uuid REFERENCES categories(id),
  price numeric(12,2) NOT NULL,
  cost numeric(12,2) DEFAULT 0 NOT NULL,
  stock_quantity integer DEFAULT 0 NOT NULL,
  min_stock_level integer DEFAULT 10,
  description text,
  image_url text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  base_unit text DEFAULT 'pcs',
  pcs_per_base_unit integer DEFAULT 1 NOT NULL,
  price_per_pcs numeric(12,2) DEFAULT 0,
  stock_pcs integer DEFAULT 0 NOT NULL
);

-- Product units table
CREATE TABLE IF NOT EXISTS product_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  unit_name text NOT NULL,
  conversion_factor numeric(12,4) DEFAULT 1 NOT NULL,
  is_base_unit boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  UNIQUE(product_id, unit_name)
);

-- Sales table
CREATE TABLE IF NOT EXISTS sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_number text UNIQUE NOT NULL,
  customer_name text,
  subtotal numeric(12,2) NOT NULL,
  tax_amount numeric(12,2) DEFAULT 0 NOT NULL,
  total_amount numeric(12,2) NOT NULL,
  payment_method payment_method NOT NULL,
  payment_received numeric(12,2) NOT NULL,
  change_amount numeric(12,2) DEFAULT 0,
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  cashier_id uuid REFERENCES profiles(id),
  invoice_status invoice_status DEFAULT 'lunas'::invoice_status
);

-- Sale items table
CREATE TABLE IF NOT EXISTS sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid REFERENCES sales(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  quantity integer NOT NULL,
  unit_price numeric(12,2) NOT NULL,
  subtotal numeric(12,2) NOT NULL,
  created_at timestamptz DEFAULT now(),
  discount numeric(10,2) DEFAULT 0,
  unit_id uuid REFERENCES product_units(id),
  unit_type text DEFAULT 'base_unit'
);

-- Stock movements table
CREATE TABLE IF NOT EXISTS stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  transaction_type transaction_type NOT NULL,
  quantity integer NOT NULL,
  unit_cost numeric(12,2),
  reference_number text,
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  unit_id uuid REFERENCES product_units(id),
  unit_type text DEFAULT 'base_unit'
);

-- Settings table
CREATE TABLE IF NOT EXISTS settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value text,
  description text,
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);

-- =====================================================
-- 3. INDEXES FOR PERFORMANCE
-- =====================================================

-- Products indexes
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_products_stock_quantity ON products(stock_quantity);
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);

-- Sales indexes
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice_status ON sales(invoice_status);
CREATE INDEX IF NOT EXISTS idx_sales_payment_method ON sales(payment_method);

-- Sale items indexes
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);

-- Stock movements indexes
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_transaction_type ON stock_movements(transaction_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created_at ON stock_movements(created_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);

-- Product units indexes
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);

-- Profiles indexes
CREATE INDEX IF NOT EXISTS idx_profiles_role ON profiles(role);

-- Categories indexes
CREATE INDEX IF NOT EXISTS idx_categories_name ON categories(name);

-- Settings indexes
CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);

-- =====================================================
-- 4. HELPER FUNCTIONS
-- =====================================================

-- Function to get user role safely
CREATE OR REPLACE FUNCTION get_user_role(user_id uuid)
RETURNS user_role
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  user_role_result user_role;
BEGIN
  SELECT role INTO user_role_result
  FROM profiles
  WHERE id = user_id;
  
  RETURN COALESCE(user_role_result, 'cashier'::user_role);
END;
$$;

-- Function to generate sale numbers
CREATE OR REPLACE FUNCTION generate_sale_number()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  sale_number text;
  counter integer;
BEGIN
  -- Get today's date in YYYYMMDD format
  sale_number := 'SALE-' || to_char(now(), 'YYYYMMDD') || '-';
  
  -- Get the count of sales today
  SELECT COUNT(*) + 1 INTO counter
  FROM sales
  WHERE created_at >= CURRENT_DATE;
  
  -- Pad with zeros to make it 4 digits
  sale_number := sale_number || LPAD(counter::text, 4, '0');
  
  RETURN sale_number;
END;
$$;

-- Function to update product stock with units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  pcs_per_unit integer;
  stock_change_pcs integer;
BEGIN
  -- Get the pcs per base unit for the product
  SELECT pcs_per_base_unit INTO pcs_per_unit
  FROM products
  WHERE id = NEW.product_id;
  
  -- Calculate stock change in pieces
  IF NEW.unit_type = 'pcs' THEN
    stock_change_pcs := NEW.quantity;
  ELSE
    -- For base_unit, multiply by conversion factor
    stock_change_pcs := NEW.quantity * COALESCE(pcs_per_unit, 1);
  END IF;
  
  -- Update stock based on transaction type
  IF NEW.transaction_type = 'inbound' THEN
    -- Add stock
    IF NEW.unit_type = 'pcs' THEN
      UPDATE products 
      SET 
        stock_pcs = stock_pcs + NEW.quantity,
        stock_quantity = stock_quantity + (NEW.quantity::numeric / COALESCE(pcs_per_unit, 1)),
        updated_at = now()
      WHERE id = NEW.product_id;
    ELSE
      UPDATE products 
      SET 
        stock_quantity = stock_quantity + NEW.quantity,
        stock_pcs = stock_pcs + stock_change_pcs,
        updated_at = now()
      WHERE id = NEW.product_id;
    END IF;
  ELSIF NEW.transaction_type = 'outbound' THEN
    -- Reduce stock
    IF NEW.unit_type = 'pcs' THEN
      UPDATE products 
      SET 
        stock_pcs = GREATEST(0, stock_pcs - NEW.quantity),
        stock_quantity = GREATEST(0, stock_quantity - (NEW.quantity::numeric / COALESCE(pcs_per_unit, 1))),
        updated_at = now()
      WHERE id = NEW.product_id;
    ELSE
      UPDATE products 
      SET 
        stock_quantity = GREATEST(0, stock_quantity - NEW.quantity),
        stock_pcs = GREATEST(0, stock_pcs - stock_change_pcs),
        updated_at = now()
      WHERE id = NEW.product_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Function to handle new user registration
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only create profile if it doesn't exist
  INSERT INTO public.profiles (id, full_name, role, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New User'),
    'cashier'::user_role,
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;
  
  RETURN NEW;
END;
$$;

-- Function to delete user completely
CREATE OR REPLACE FUNCTION delete_user(user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete from auth.users (this will cascade to profiles due to FK)
  DELETE FROM auth.users WHERE id = user_id;
END;
$$;

-- =====================================================
-- 5. ROW LEVEL SECURITY SETUP
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- Profiles policies
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles" ON profiles
  FOR SELECT TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

CREATE POLICY "Admins can update all profiles" ON profiles
  FOR UPDATE TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

CREATE POLICY "Admins can insert profiles" ON profiles
  FOR INSERT TO public
  WITH CHECK (get_user_role(auth.uid()) = 'admin'::user_role);

-- Categories policies
CREATE POLICY "All authenticated users can view categories" ON categories
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage categories" ON categories
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Products policies
CREATE POLICY "All authenticated users can view products" ON products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage products" ON products
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Product units policies
CREATE POLICY "All authenticated users can view product units" ON product_units
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage product units" ON product_units
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Sales policies
CREATE POLICY "All authenticated users can view sales" ON sales
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create sales" ON sales
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins can manage all sales" ON sales
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

-- Sale items policies
CREATE POLICY "Users can view sale items" ON sale_items
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Users can create sale items" ON sale_items
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Admins can manage sale items" ON sale_items
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

-- Stock movements policies
CREATE POLICY "All authenticated users can view stock movements" ON stock_movements
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create stock movements" ON stock_movements
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins, stockists, and cashiers can update stock movements" ON stock_movements
  FOR UPDATE TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

CREATE POLICY "Admins, stockists, and cashiers can delete stock movements" ON stock_movements
  FOR DELETE TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

-- Settings policies
CREATE POLICY "All authenticated users can view settings" ON settings
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins can manage settings" ON settings
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

-- =====================================================
-- 6. TRIGGERS SETUP
-- =====================================================

-- Drop existing triggers if they exist
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;

-- Create trigger for automatic profile creation
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Create trigger for stock updates
CREATE TRIGGER update_product_stock_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_product_stock_with_units();

-- =====================================================
-- 7. STORAGE SETUP
-- =====================================================

-- Create storage bucket for company assets
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for company assets
CREATE POLICY "Anyone can view company assets" ON storage.objects
  FOR SELECT USING (bucket_id = 'company-assets');

CREATE POLICY "Authenticated users can upload company assets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'company-assets');

CREATE POLICY "Authenticated users can update company assets" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'company-assets');

CREATE POLICY "Authenticated users can delete company assets" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'company-assets');

-- =====================================================
-- 8. AUTH CONFIGURATION
-- =====================================================

-- Disable email confirmation for easier development
UPDATE auth.config 
SET 
  enable_signup = true,
  enable_email_confirmations = false,
  enable_phone_confirmations = false
WHERE true;

-- =====================================================
-- 9. SAMPLE DATA
-- =====================================================

-- Insert sample categories
INSERT INTO categories (id, name, description) VALUES
  ('550e8400-e29b-41d4-a716-446655440001', 'Electronics', 'Electronic devices and accessories'),
  ('550e8400-e29b-41d4-a716-446655440002', 'Clothing', 'Apparel and fashion items'),
  ('550e8400-e29b-41d4-a716-446655440003', 'Food & Beverage', 'Food and drink products'),
  ('550e8400-e29b-41d4-a716-446655440004', 'Books', 'Books and educational materials'),
  ('550e8400-e29b-41d4-a716-446655440005', 'Home & Garden', 'Home improvement and gardening')
ON CONFLICT (id) DO NOTHING;

-- Insert sample products with multi-unit support
INSERT INTO products (
  id, name, sku, category_id, price, cost, stock_quantity, min_stock_level, 
  description, is_active, base_unit, pcs_per_base_unit, price_per_pcs, stock_pcs
) VALUES
  (
    '660e8400-e29b-41d4-a716-446655440001', 
    'Smartphone Samsung Galaxy', 
    'PHONE-001', 
    '550e8400-e29b-41d4-a716-446655440001', 
    3000000, 2500000, 5, 2, 
    'Latest Samsung Galaxy smartphone with advanced features', 
    true, 'pcs', 1, 3000000, 5
  ),
  (
    '660e8400-e29b-41d4-a716-446655440002', 
    'T-Shirt Cotton Premium', 
    'SHIRT-001', 
    '550e8400-e29b-41d4-a716-446655440002', 
    150000, 100000, 10, 5, 
    'Premium cotton t-shirt available in various sizes', 
    true, 'pcs', 1, 150000, 10
  ),
  (
    '660e8400-e29b-41d4-a716-446655440003', 
    'Instant Noodles', 
    'FOOD-001', 
    '550e8400-e29b-41d4-a716-446655440003', 
    60000, 45000, 20, 10, 
    'Delicious instant noodles - 1 dus contains 24 pcs', 
    true, 'dus', 24, 2500, 480
  ),
  (
    '660e8400-e29b-41d4-a716-446655440004', 
    'Programming Book', 
    'BOOK-001', 
    '550e8400-e29b-41d4-a716-446655440004', 
    250000, 200000, 15, 3, 
    'Comprehensive programming guide for beginners', 
    true, 'pcs', 1, 250000, 15
  ),
  (
    '660e8400-e29b-41d4-a716-446655440005', 
    'Garden Tools Set', 
    'GARDEN-001', 
    '550e8400-e29b-41d4-a716-446655440005', 
    450000, 350000, 8, 2, 
    'Complete set of essential garden tools', 
    true, 'pcs', 1, 450000, 8
  )
ON CONFLICT (id) DO NOTHING;

-- Insert sample settings
INSERT INTO settings (key, value, description) VALUES
  ('store_name', 'Awanvisual Demo Store', 'Name of the store'),
  ('store_address', 'Jl. Demo No. 123, Jakarta', 'Store address'),
  ('store_phone', '+62 21 1234 5678', 'Store phone number'),
  ('store_email', 'demo@awanvisual.com', 'Store email address'),
  ('store_website', 'www.awanvisual.com', 'Store website'),
  ('receipt_header', 'Thank you for shopping with us!', 'Header text for receipts'),
  ('receipt_footer', 'Visit us again soon!', 'Footer text for receipts'),
  ('payment_note_line1', 'Harga BCA : [amount]/PUTRA INDRAWAN', 'Payment note line 1'),
  ('payment_note_line2', 'No. Rekening: 7840656905', 'Payment note line 2'),
  ('low_stock_threshold', '10', 'Threshold for low stock alerts'),
  ('low_stock_alerts', 'true', 'Enable low stock alerts'),
  ('daily_sales_summary', 'false', 'Enable daily sales summary'),
  ('print_receipt_auto', 'true', 'Auto-print receipt after sale')
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = now();

-- =====================================================
-- 10. GRANT PERMISSIONS
-- =====================================================

-- Grant necessary permissions to authenticated users
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant storage permissions
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;

-- =====================================================
-- 11. VERIFICATION QUERIES
-- =====================================================

-- Verify setup
DO $$
BEGIN
  RAISE NOTICE '=== DATABASE SETUP VERIFICATION ===';
  RAISE NOTICE 'Tables created: %', (
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_name IN ('profiles', 'categories', 'products', 'product_units', 'sales', 'sale_items', 'stock_movements', 'settings')
  );
  RAISE NOTICE 'Sample categories: %', (SELECT COUNT(*) FROM categories);
  RAISE NOTICE 'Sample products: %', (SELECT COUNT(*) FROM products);
  RAISE NOTICE 'Sample settings: %', (SELECT COUNT(*) FROM settings);
  RAISE NOTICE 'Storage bucket created: %', (SELECT COUNT(*) FROM storage.buckets WHERE id = 'company-assets');
  RAISE NOTICE '=== SETUP COMPLETE ===';
END $$;