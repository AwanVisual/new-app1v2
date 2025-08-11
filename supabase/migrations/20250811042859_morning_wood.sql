/*
  # Complete POS Database Setup
  
  This file contains the complete database schema for the POS (Point of Sale) application.
  
  ## Features Included:
  1. Authentication & User Management
  2. Product Management with Multi-Unit Support
  3. Category Management
  4. Sales & Transaction Processing
  5. Stock Movement Tracking
  6. Settings Management
  7. Row Level Security (RLS)
  8. Helper Functions
  
  ## Tables Created:
  - users (Supabase Auth integration)
  - profiles (User profiles with roles)
  - categories (Product categories)
  - products (Product catalog with multi-unit support)
  - product_units (Unit conversion system)
  - sales (Sales transactions)
  - sale_items (Individual sale line items)
  - stock_movements (Inventory tracking)
  - settings (Application configuration)
  
  ## Security:
  - Row Level Security enabled on all tables
  - Role-based access control (admin, stockist, cashier)
  - Proper authentication policies
*/

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types/enums
CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');
CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');

-- Helper function to get user role
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

-- Function to handle new user creation
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

-- Function to generate sale numbers
CREATE OR REPLACE FUNCTION generate_sale_number()
RETURNS text AS $$
DECLARE
  today_date text;
  sequence_num integer;
  sale_number text;
BEGIN
  today_date := to_char(CURRENT_DATE, 'YYYYMMDD');
  
  SELECT COALESCE(MAX(CAST(SUBSTRING(sale_number FROM 14) AS INTEGER)), 0) + 1
  INTO sequence_num
  FROM sales
  WHERE sale_number LIKE 'SALE-' || today_date || '-%';
  
  sale_number := 'SALE-' || today_date || '-' || LPAD(sequence_num::text, 4, '0');
  
  RETURN sale_number;
END;
$$ LANGUAGE plpgsql;

-- Function to update product stock with units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS trigger AS $$
DECLARE
  pcs_per_base_unit integer;
  stock_change_pcs integer;
  current_stock_pcs integer;
  current_base_stock numeric;
BEGIN
  -- Get product's pcs per base unit
  SELECT products.pcs_per_base_unit, products.stock_pcs, products.stock_quantity
  INTO pcs_per_base_unit, current_stock_pcs, current_base_stock
  FROM products
  WHERE id = NEW.product_id;
  
  -- Calculate stock change in pieces
  IF NEW.unit_type = 'pcs' THEN
    stock_change_pcs := NEW.quantity;
  ELSE
    -- base_unit
    stock_change_pcs := NEW.quantity * pcs_per_base_unit;
  END IF;
  
  -- Apply stock change based on transaction type
  IF NEW.transaction_type = 'inbound' THEN
    -- Add stock
    UPDATE products 
    SET 
      stock_pcs = COALESCE(stock_pcs, 0) + stock_change_pcs,
      stock_quantity = (COALESCE(stock_pcs, 0) + stock_change_pcs)::numeric / pcs_per_base_unit,
      updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'outbound' THEN
    -- Reduce stock
    UPDATE products 
    SET 
      stock_pcs = GREATEST(0, COALESCE(stock_pcs, 0) - stock_change_pcs),
      stock_quantity = GREATEST(0, (COALESCE(stock_pcs, 0) - stock_change_pcs)::numeric / pcs_per_base_unit),
      updated_at = now()
    WHERE id = NEW.product_id;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to delete user (admin only)
CREATE OR REPLACE FUNCTION delete_user(user_id uuid)
RETURNS void AS $$
BEGIN
  -- Check if current user is admin
  IF get_user_role(auth.uid()) != 'admin' THEN
    RAISE EXCEPTION 'Only admins can delete users';
  END IF;
  
  -- Delete from auth.users (this will cascade to profiles)
  DELETE FROM auth.users WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create profiles table
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role user_role NOT NULL DEFAULT 'cashier',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

-- Create products table
CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  sku text UNIQUE NOT NULL,
  category_id uuid REFERENCES categories(id),
  price numeric(12,2) NOT NULL,
  cost numeric(12,2) NOT NULL DEFAULT 0,
  stock_quantity integer NOT NULL DEFAULT 0,
  min_stock_level integer DEFAULT 10,
  description text,
  image_url text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  base_unit text DEFAULT 'pcs',
  pcs_per_base_unit integer DEFAULT 1,
  price_per_pcs numeric(12,2) DEFAULT 0,
  stock_pcs integer DEFAULT 0
);

-- Create product_units table
CREATE TABLE IF NOT EXISTS product_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  unit_name text NOT NULL,
  conversion_factor numeric(12,4) NOT NULL DEFAULT 1,
  is_base_unit boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id),
  UNIQUE(product_id, unit_name)
);

-- Create sales table
CREATE TABLE IF NOT EXISTS sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_number text UNIQUE NOT NULL,
  customer_name text,
  subtotal numeric(12,2) NOT NULL,
  tax_amount numeric(12,2) NOT NULL DEFAULT 0,
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

-- Create sale_items table
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

-- Create stock_movements table
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

-- Create settings table
CREATE TABLE IF NOT EXISTS settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  key text UNIQUE NOT NULL,
  value text,
  description text,
  updated_at timestamptz DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice_status ON sales(invoice_status);
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);

-- Enable Row Level Security on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- RLS Policies for profiles
CREATE POLICY "Users can view their own profile"
  ON profiles FOR SELECT
  TO public
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own profile"
  ON profiles FOR UPDATE
  TO public
  USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles"
  ON profiles FOR SELECT
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can update all profiles"
  ON profiles FOR UPDATE
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can insert profiles"
  ON profiles FOR INSERT
  TO public
  WITH CHECK (get_user_role(auth.uid()) = 'admin');

-- RLS Policies for categories
CREATE POLICY "All authenticated users can view categories"
  ON categories FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage categories"
  ON categories FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role]));

-- RLS Policies for products
CREATE POLICY "All authenticated users can view products"
  ON products FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage products"
  ON products FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role]));

-- RLS Policies for product_units
CREATE POLICY "All authenticated users can view product units"
  ON product_units FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage product units"
  ON product_units FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role]));

-- RLS Policies for sales
CREATE POLICY "All authenticated users can view sales"
  ON sales FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create sales"
  ON sales FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins can manage all sales"
  ON sales FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- RLS Policies for sale_items
CREATE POLICY "Users can view sale items"
  ON sale_items FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Users can create sale items"
  ON sale_items FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Admins can manage sale items"
  ON sale_items FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- RLS Policies for stock_movements
CREATE POLICY "All authenticated users can view stock movements"
  ON stock_movements FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create stock movements"
  ON stock_movements FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins, stockists, and cashiers can update stock movements"
  ON stock_movements FOR UPDATE
  TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

CREATE POLICY "Admins, stockists, and cashiers can delete stock movements"
  ON stock_movements FOR DELETE
  TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

-- RLS Policies for settings
CREATE POLICY "All authenticated users can view settings"
  ON settings FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can manage settings"
  ON settings FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- Create triggers
CREATE OR REPLACE TRIGGER handle_new_user_trigger
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

CREATE OR REPLACE TRIGGER update_product_stock_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW EXECUTE FUNCTION update_product_stock_with_units();

-- Insert default settings
INSERT INTO settings (key, value, description) VALUES
  ('store_name', 'Awanvisual Store', 'Name of the store'),
  ('store_address', 'Jl. Contoh No. 123, Jakarta', 'Store address'),
  ('store_phone', '+62 21 1234 5678', 'Store phone number'),
  ('store_email', 'info@awanvisual.com', 'Store email address'),
  ('store_website', 'www.awanvisual.com', 'Store website'),
  ('receipt_header', 'Terima kasih telah berbelanja!', 'Receipt header message'),
  ('receipt_footer', 'Barang yang sudah dibeli tidak dapat dikembalikan', 'Receipt footer message'),
  ('payment_note_line1', 'Transfer BCA: [amount]/AWANVISUAL', 'Payment note line 1'),
  ('payment_note_line2', 'No. Rekening: 1234567890', 'Payment note line 2'),
  ('low_stock_threshold', '10', 'Low stock alert threshold'),
  ('low_stock_alerts', 'true', 'Enable low stock alerts'),
  ('daily_sales_summary', 'false', 'Enable daily sales summary'),
  ('print_receipt_auto', 'true', 'Auto print receipt after sale')
ON CONFLICT (key) DO NOTHING;

-- Insert default categories
INSERT INTO categories (name, description) VALUES
  ('Electronics', 'Electronic devices and accessories'),
  ('Clothing', 'Apparel and fashion items'),
  ('Food & Beverage', 'Food and drink products'),
  ('Books', 'Books and educational materials'),
  ('Home & Garden', 'Home improvement and garden supplies')
ON CONFLICT (name) DO NOTHING;

-- Insert sample products
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
  INSERT INTO products (name, sku, category_id, price, cost, stock_quantity, base_unit, pcs_per_base_unit, price_per_pcs, stock_pcs, description) VALUES
    ('Smartphone Samsung Galaxy', 'PHONE-001', electronics_id, 5000000, 4500000, 10, 'pcs', 1, 5000000, 10, 'Latest Samsung Galaxy smartphone'),
    ('Laptop ASUS VivoBook', 'LAPTOP-001', electronics_id, 8000000, 7200000, 5, 'pcs', 1, 8000000, 5, 'ASUS VivoBook 14 inch laptop'),
    ('T-Shirt Cotton', 'SHIRT-001', clothing_id, 150000, 100000, 50, 'pcs', 1, 150000, 50, 'Premium cotton t-shirt'),
    ('Jeans Denim', 'JEANS-001', clothing_id, 300000, 200000, 30, 'pcs', 1, 300000, 30, 'Classic denim jeans'),
    ('Mineral Water', 'WATER-001', food_id, 60000, 48000, 20, 'dus', 24, 2500, 480, '24 bottles per box'),
    ('Instant Noodles', 'NOODLE-001', food_id, 36000, 30000, 15, 'dus', 12, 3000, 180, '12 packs per box')
  ON CONFLICT (sku) DO NOTHING;
END $$;

-- Create storage bucket for company assets (if not exists)
INSERT INTO storage.buckets (id, name, public) 
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies for company assets
CREATE POLICY "Public can view company assets"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'company-assets');

CREATE POLICY "Authenticated users can upload company assets"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'company-assets');

CREATE POLICY "Authenticated users can update company assets"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'company-assets');

CREATE POLICY "Admins can delete company assets"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'company-assets' AND get_user_role(auth.uid()) = 'admin');

-- Disable email confirmation (for development)
UPDATE auth.config 
SET email_confirm = false, 
    email_change_confirm = false,
    sms_confirm = false
WHERE true;

-- Create default admin user (optional - uncomment and modify as needed)
/*
DO $$
DECLARE
  admin_user_id uuid;
BEGIN
  -- Insert admin user
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    created_at,
    updated_at,
    raw_app_meta_data,
    raw_user_meta_data,
    is_super_admin,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    'admin@awanvisual.com',
    crypt('admin123', gen_salt('bf')),
    now(),
    now(),
    now(),
    '{"provider": "email", "providers": ["email"]}',
    '{"full_name": "System Administrator"}',
    false,
    '',
    '',
    '',
    ''
  )
  RETURNING id INTO admin_user_id;
  
  -- Update profile to admin role
  UPDATE profiles SET role = 'admin' WHERE id = admin_user_id;
  
EXCEPTION WHEN unique_violation THEN
  -- Admin user already exists, do nothing
  NULL;
END $$;
*/

-- Final verification queries (optional - for testing)
-- SELECT 'Database setup completed successfully!' as status;
-- SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;
-- SELECT * FROM categories LIMIT 5;
-- SELECT name, sku, price, stock_quantity, base_unit FROM products LIMIT 5;