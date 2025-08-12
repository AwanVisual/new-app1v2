/*
  # Complete POS Database Setup
  
  This SQL file contains everything needed to set up a complete POS system database:
  
  1. Authentication Configuration
  2. Custom Types (Enums)
  3. Core Tables with RLS
  4. Security Policies
  5. Functions and Triggers
  6. Storage Setup
  7. Indexes for Performance
  8. Sample Data
  
  Run this entire file in Supabase SQL Editor to set up the complete system.
*/

-- =====================================================
-- 1. AUTHENTICATION CONFIGURATION
-- =====================================================

-- Disable email confirmation for easier testing
UPDATE auth.config 
SET email_confirm_change_enabled = false, 
    email_autoconfirm = true;

-- =====================================================
-- 2. CUSTOM TYPES (ENUMS)
-- =====================================================

-- User roles enum
CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');

-- Payment methods enum  
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');

-- Transaction types for stock movements
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');

-- Invoice status enum
CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');

-- =====================================================
-- 3. CORE TABLES
-- =====================================================

-- Users table (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

-- User profiles table
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

-- Products table with multi-unit support
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

-- Product units table for multi-unit support
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
-- 4. ENABLE ROW LEVEL SECURITY
-- =====================================================

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- 5. HELPER FUNCTIONS
-- =====================================================

-- Function to get user role
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
  today_date text;
  sequence_num integer;
BEGIN
  today_date := to_char(now(), 'YYYYMMDD');
  
  SELECT COALESCE(MAX(CAST(SUBSTRING(sale_number FROM 14) AS integer)), 0) + 1
  INTO sequence_num
  FROM sales
  WHERE sale_number LIKE 'SALE-' || today_date || '-%';
  
  RETURN 'SALE-' || today_date || '-' || LPAD(sequence_num::text, 4, '0');
END;
$$ LANGUAGE plpgsql;

-- Function to update product stock with units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS trigger AS $$
BEGIN
  IF NEW.unit_type = 'pcs' THEN
    -- Direct pieces update
    IF NEW.transaction_type = 'inbound' THEN
      UPDATE products 
      SET stock_pcs = stock_pcs + NEW.quantity,
          stock_quantity = stock_quantity + (NEW.quantity::numeric / COALESCE(pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
      UPDATE products 
      SET stock_pcs = GREATEST(0, stock_pcs - NEW.quantity),
          stock_quantity = GREATEST(0, stock_quantity - (NEW.quantity::numeric / COALESCE(pcs_per_base_unit, 1)))
      WHERE id = NEW.product_id;
    END IF;
  ELSE
    -- Base unit update
    IF NEW.transaction_type = 'inbound' THEN
      UPDATE products 
      SET stock_quantity = stock_quantity + NEW.quantity,
          stock_pcs = stock_pcs + (NEW.quantity * COALESCE(pcs_per_base_unit, 1))
      WHERE id = NEW.product_id;
    ELSIF NEW.transaction_type = 'outbound' THEN
      UPDATE products 
      SET stock_quantity = GREATEST(0, stock_quantity - NEW.quantity),
          stock_pcs = GREATEST(0, stock_pcs - (NEW.quantity * COALESCE(pcs_per_base_unit, 1)))
      WHERE id = NEW.product_id;
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to handle new user registration
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.users (id)
  VALUES (NEW.id);
  
  INSERT INTO public.profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'cashier'::user_role
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to delete user completely
CREATE OR REPLACE FUNCTION delete_user(user_id uuid)
RETURNS void AS $$
BEGIN
  -- Delete from auth.users (will cascade to other tables)
  DELETE FROM auth.users WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 6. TRIGGERS
-- =====================================================

-- Trigger for new user registration
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Trigger for stock updates
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
CREATE TRIGGER update_product_stock_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_product_stock_with_units();

-- =====================================================
-- 7. ROW LEVEL SECURITY POLICIES
-- =====================================================

-- Users policies
CREATE POLICY "Users can view own data" ON users
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

-- Profiles policies
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT TO public
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE TO public
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
-- 8. STORAGE SETUP
-- =====================================================

-- Create storage bucket for company assets
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for company assets
CREATE POLICY "Public can view company assets" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'company-assets');

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
-- 9. INDEXES FOR PERFORMANCE
-- =====================================================

-- Products indexes
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_products_stock_quantity ON products(stock_quantity);

-- Product units indexes
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);

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

-- Settings indexes
CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);

-- =====================================================
-- 10. GRANT PERMISSIONS
-- =====================================================

-- Grant usage on schemas
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA storage TO authenticated;

-- Grant permissions on tables
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- Grant permissions on storage
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;

-- =====================================================
-- 11. SAMPLE DATA
-- =====================================================

-- Insert default categories
INSERT INTO categories (name, description) VALUES
('Electronics', 'Electronic devices and accessories'),
('Clothing', 'Apparel and fashion items'),
('Food & Beverage', 'Food and drink products'),
('Home & Garden', 'Home improvement and gardening'),
('Books & Media', 'Books, magazines, and media'),
('Sports & Outdoors', 'Sports equipment and outdoor gear'),
('Health & Beauty', 'Health and beauty products'),
('Toys & Games', 'Toys and gaming products')
ON CONFLICT (name) DO NOTHING;

-- Insert sample products with multi-unit support
INSERT INTO products (
  name, sku, price, cost, stock_quantity, description, 
  base_unit, pcs_per_base_unit, price_per_pcs, stock_pcs,
  category_id
) 
SELECT 
  'Smartphone Samsung Galaxy', 'PHONE-001', 5000000, 4500000, 2, 'Latest Samsung Galaxy smartphone',
  'dus', 10, 500000, 20,
  c.id
FROM categories c WHERE c.name = 'Electronics'
UNION ALL
SELECT 
  'T-Shirt Cotton Basic', 'SHIRT-001', 150000, 100000, 5, 'Basic cotton t-shirt',
  'lusin', 12, 12500, 60,
  c.id
FROM categories c WHERE c.name = 'Clothing'
UNION ALL
SELECT 
  'Mineral Water 600ml', 'WATER-001', 36000, 30000, 10, 'Natural mineral water',
  'dus', 24, 1500, 240,
  c.id
FROM categories c WHERE c.name = 'Food & Beverage'
UNION ALL
SELECT 
  'Notebook A4', 'BOOK-001', 60000, 45000, 3, 'A4 size notebook',
  'lusin', 12, 5000, 36,
  c.id
FROM categories c WHERE c.name = 'Books & Media'
ON CONFLICT (sku) DO NOTHING;

-- Insert default settings
INSERT INTO settings (key, value, description) VALUES
('store_name', 'Awanvisual Store', 'Name of the store'),
('store_address', 'Jl. Contoh No. 123, Jakarta', 'Store address'),
('store_phone', '+62 21 1234567', 'Store phone number'),
('store_email', 'info@awanvisual.com', 'Store email address'),
('store_website', 'www.awanvisual.com', 'Store website'),
('receipt_header', 'Terima kasih telah berbelanja!', 'Header text for receipts'),
('receipt_footer', 'Barang yang sudah dibeli tidak dapat dikembalikan', 'Footer text for receipts'),
('payment_note_line1', 'Transfer BCA: [amount]/AWANVISUAL', 'Payment note line 1'),
('payment_note_line2', 'No. Rekening: 1234567890', 'Payment note line 2'),
('low_stock_threshold', '10', 'Threshold for low stock alerts'),
('low_stock_alerts', 'true', 'Enable low stock alerts'),
('daily_sales_summary', 'false', 'Enable daily sales summary'),
('print_receipt_auto', 'true', 'Auto print receipt after sale')
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = now();

-- =====================================================
-- 12. FINAL SETUP VERIFICATION
-- =====================================================

-- Verify all tables exist
DO $$
DECLARE
  table_count integer;
BEGIN
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name IN ('users', 'profiles', 'categories', 'products', 'product_units', 'sales', 'sale_items', 'stock_movements', 'settings');
  
  IF table_count = 9 THEN
    RAISE NOTICE 'SUCCESS: All 9 core tables created successfully!';
  ELSE
    RAISE NOTICE 'WARNING: Only % out of 9 tables found', table_count;
  END IF;
END $$;

-- Verify RLS is enabled
DO $$
DECLARE
  rls_count integer;
BEGIN
  SELECT COUNT(*) INTO rls_count
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' 
  AND c.relname IN ('users', 'profiles', 'categories', 'products', 'product_units', 'sales', 'sale_items', 'stock_movements', 'settings')
  AND c.relrowsecurity = true;
  
  IF rls_count = 9 THEN
    RAISE NOTICE 'SUCCESS: RLS enabled on all tables!';
  ELSE
    RAISE NOTICE 'WARNING: RLS only enabled on % out of 9 tables', rls_count;
  END IF;
END $$;

-- Verify functions exist
DO $$
DECLARE
  function_count integer;
BEGIN
  SELECT COUNT(*) INTO function_count
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' 
  AND p.proname IN ('get_user_role', 'generate_sale_number', 'update_product_stock_with_units', 'handle_new_user', 'delete_user');
  
  IF function_count >= 5 THEN
    RAISE NOTICE 'SUCCESS: All required functions created!';
  ELSE
    RAISE NOTICE 'WARNING: Only % out of 5 functions found', function_count;
  END IF;
END $$;

-- Final success message
DO $$
BEGIN
  RAISE NOTICE '🎉 DATABASE SETUP COMPLETE! 🎉';
  RAISE NOTICE 'Your POS system database is ready to use.';
  RAISE NOTICE 'You can now start using the application.';
END $$;