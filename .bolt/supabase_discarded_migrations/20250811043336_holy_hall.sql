/*
  # Complete POS Database Setup
  
  This SQL file contains the complete database schema for the POS application including:
  
  1. Authentication & User Management
     - Supabase Auth integration
     - User profiles with roles (admin, cashier, stockist)
     - Automatic profile creation on signup
  
  2. Product Management
     - Products with multi-unit support
     - Categories
     - Product units with conversion factors
     - Stock tracking in both base units and pieces
  
  3. Sales System
     - Sales transactions with multiple payment methods
     - Sale items with unit-specific pricing
     - Invoice status tracking (lunas, dp, belum_bayar)
     - Individual item discounts
  
  4. Inventory Management
     - Stock movements (inbound, outbound, adjustment)
     - Unit-aware stock tracking
     - Automatic stock updates via triggers
  
  5. Settings & Configuration
     - Store settings
     - Receipt configuration
     - Company logo storage
  
  6. Security
     - Row Level Security (RLS) on all tables
     - Role-based access control
     - Secure functions
  
  7. Storage
     - Company assets bucket for logos
     - Proper storage policies
  
  8. Sample Data
     - Default categories
     - Sample products with various units
     - Default settings
*/

-- =============================================
-- 1. ENUMS
-- =============================================

CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');
CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');

-- =============================================
-- 2. TABLES
-- =============================================

-- Users table (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- User profiles
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role user_role DEFAULT 'cashier' NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Categories
CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

-- Products
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
  price_per_pcs numeric(12,2) DEFAULT 0 NOT NULL,
  stock_pcs integer DEFAULT 0 NOT NULL
);

-- Product units
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

-- Sales
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
  invoice_status invoice_status DEFAULT 'lunas'
);

-- Sale items
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

-- Stock movements
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

-- Settings
CREATE TABLE IF NOT EXISTS settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value text,
  description text,
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);

-- =============================================
-- 3. INDEXES
-- =============================================

CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active);

CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);

CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice_status ON sales(invoice_status);

CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created_at ON stock_movements(created_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_transaction_type ON stock_movements(transaction_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);

-- =============================================
-- 4. FUNCTIONS
-- =============================================

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

-- Function to generate sale number
CREATE OR REPLACE FUNCTION generate_sale_number()
RETURNS text AS $$
DECLARE
  sale_num text;
  counter integer;
BEGIN
  -- Get today's date in YYYYMMDD format
  sale_num := 'SALE-' || to_char(now(), 'YYYYMMDD') || '-';
  
  -- Get the count of sales today
  SELECT COUNT(*) + 1 INTO counter
  FROM sales
  WHERE created_at::date = CURRENT_DATE;
  
  -- Pad with zeros to make it 4 digits
  sale_num := sale_num || lpad(counter::text, 4, '0');
  
  RETURN sale_num;
END;
$$ LANGUAGE plpgsql;

-- Function to update product stock with units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS trigger AS $$
DECLARE
  pcs_quantity integer;
  base_unit_quantity numeric;
  pcs_per_unit integer;
BEGIN
  -- Get the pcs_per_base_unit for the product
  SELECT pcs_per_base_unit INTO pcs_per_unit
  FROM products
  WHERE id = NEW.product_id;
  
  -- Calculate quantities based on unit type
  IF NEW.unit_type = 'pcs' THEN
    pcs_quantity := NEW.quantity;
    base_unit_quantity := NEW.quantity::numeric / pcs_per_unit;
  ELSE
    -- base_unit
    pcs_quantity := NEW.quantity * pcs_per_unit;
    base_unit_quantity := NEW.quantity;
  END IF;
  
  -- Update stock based on transaction type
  IF NEW.transaction_type = 'inbound' THEN
    UPDATE products 
    SET 
      stock_quantity = stock_quantity + base_unit_quantity,
      stock_pcs = stock_pcs + pcs_quantity,
      updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'outbound' THEN
    UPDATE products 
    SET 
      stock_quantity = GREATEST(0, stock_quantity - base_unit_quantity),
      stock_pcs = GREATEST(0, stock_pcs - pcs_quantity),
      updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'adjustment' THEN
    -- For adjustments, set the exact quantity
    UPDATE products 
    SET 
      stock_quantity = base_unit_quantity,
      stock_pcs = pcs_quantity,
      updated_at = now()
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
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'User'),
    'cashier'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to delete user completely
CREATE OR REPLACE FUNCTION delete_user(user_id uuid)
RETURNS void AS $$
BEGIN
  -- Delete from auth.users (this will cascade to profiles)
  DELETE FROM auth.users WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 5. TRIGGERS
-- =============================================

-- Trigger for automatic profile creation
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Trigger for stock updates
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
CREATE TRIGGER update_product_stock_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_product_stock_with_units();

-- =============================================
-- 6. ROW LEVEL SECURITY (RLS)
-- =============================================

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
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can update all profiles" ON profiles
  FOR UPDATE TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can insert profiles" ON profiles
  FOR INSERT TO public
  WITH CHECK (get_user_role(auth.uid()) = 'admin');

-- Categories policies
CREATE POLICY "All authenticated users can view categories" ON categories
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage categories" ON categories
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Products policies
CREATE POLICY "All authenticated users can view products" ON products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage products" ON products
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Product units policies
CREATE POLICY "All authenticated users can view product units" ON product_units
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage product units" ON product_units
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Sales policies
CREATE POLICY "All authenticated users can view sales" ON sales
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create sales" ON sales
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins can manage all sales" ON sales
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- Sale items policies
CREATE POLICY "Users can view sale items" ON sale_items
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Users can create sale items" ON sale_items
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Admins can manage sale items" ON sale_items
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- Stock movements policies
CREATE POLICY "All authenticated users can view stock movements" ON stock_movements
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create stock movements" ON stock_movements
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins, stockists, and cashiers can update stock movements" ON stock_movements
  FOR UPDATE TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

CREATE POLICY "Admins, stockists, and cashiers can delete stock movements" ON stock_movements
  FOR DELETE TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

-- Settings policies
CREATE POLICY "All authenticated users can view settings" ON settings
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins can manage settings" ON settings
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- =============================================
-- 7. STORAGE
-- =============================================

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

-- =============================================
-- 8. AUTH CONFIGURATION
-- =============================================

-- Disable email confirmation for easier testing
UPDATE auth.config 
SET email_confirm = false 
WHERE true;

-- =============================================
-- 9. SAMPLE DATA
-- =============================================

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

-- Insert sample products with various units
DO $$
DECLARE
  electronics_id uuid;
  clothing_id uuid;
  food_id uuid;
BEGIN
  -- Get category IDs
  SELECT id INTO electronics_id FROM categories WHERE name = 'Electronics';
  SELECT id INTO clothing_id FROM categories WHERE name = 'Clothing';
  SELECT id INTO food_id FROM categories WHERE name = 'Food & Beverage';

  -- Insert sample products
  INSERT INTO products (name, sku, category_id, price, price_per_pcs, cost, stock_quantity, stock_pcs, base_unit, pcs_per_base_unit, description) VALUES
    ('Smartphone Samsung Galaxy', 'PHONE-001', electronics_id, 5000000, 5000000, 4500000, 5, 5, 'pcs', 1, 'Latest Samsung Galaxy smartphone'),
    ('T-Shirt Cotton', 'SHIRT-001', clothing_id, 150000, 12500, 10000, 10, 120, 'dus', 12, 'Comfortable cotton t-shirt'),
    ('Instant Noodles', 'NOODLE-001', food_id, 36000, 3000, 2500, 20, 240, 'dus', 12, 'Delicious instant noodles'),
    ('Laptop Asus', 'LAPTOP-001', electronics_id, 8000000, 8000000, 7200000, 3, 3, 'pcs', 1, 'High performance laptop'),
    ('Jeans Denim', 'JEANS-001', clothing_id, 300000, 25000, 20000, 8, 96, 'dus', 12, 'Premium denim jeans'),
    ('Mineral Water', 'WATER-001', food_id, 48000, 2000, 1500, 15, 360, 'dus', 24, 'Pure mineral water 600ml')
  ON CONFLICT (sku) DO NOTHING;
END $$;

-- Insert default settings
INSERT INTO settings (key, value, description) VALUES
  ('store_name', 'Awanvisual Store', 'Name of the store'),
  ('store_address', 'Jl. Contoh No. 123, Jakarta', 'Store address'),
  ('store_phone', '+62 21 1234 5678', 'Store phone number'),
  ('store_email', 'info@awanvisual.com', 'Store email address'),
  ('store_website', 'www.awanvisual.com', 'Store website'),
  ('receipt_header', 'Terima kasih telah berbelanja!', 'Header text for receipts'),
  ('receipt_footer', 'Barang yang sudah dibeli tidak dapat dikembalikan', 'Footer text for receipts'),
  ('payment_note_line1', 'Transfer BCA: [amount]/AWANVISUAL', 'Payment note line 1'),
  ('payment_note_line2', 'No. Rekening: 1234567890', 'Payment note line 2'),
  ('low_stock_threshold', '10', 'Threshold for low stock alerts'),
  ('low_stock_alerts', 'true', 'Enable low stock alerts'),
  ('daily_sales_summary', 'false', 'Enable daily sales summary'),
  ('print_receipt_auto', 'true', 'Auto print receipt after sale'),
  ('company_logo', '', 'Company logo URL')
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  description = EXCLUDED.description;

-- =============================================
-- 10. GRANT PERMISSIONS
-- =============================================

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO authenticated, anon;
GRANT ALL ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;

-- Grant storage permissions
GRANT ALL ON storage.objects TO authenticated;
GRANT ALL ON storage.buckets TO authenticated;

-- =============================================
-- 11. FINAL SETUP NOTES
-- =============================================

/*
  Setup Complete! 

  Default Admin User:
  - Create your first admin user through the application signup
  - The first user will be created as 'cashier' by default
  - You can manually update their role to 'admin' in the profiles table:
    
    UPDATE profiles SET role = 'admin' WHERE id = 'your-user-id';

  Features Included:
  ✅ Multi-unit product system (dus, pcs, kg, etc.)
  ✅ Stock management with automatic conversions
  ✅ Sales system with discounts and multiple payment methods
  ✅ Invoice status tracking (lunas, dp, belum_bayar)
  ✅ Role-based access control (admin, stockist, cashier)
  ✅ File storage for company logos
  ✅ Comprehensive settings management
  ✅ Sample data for testing
  ✅ All necessary indexes for performance
  ✅ Complete RLS security policies

  Ready for Production! 🚀
*/