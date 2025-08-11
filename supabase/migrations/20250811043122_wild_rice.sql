/*
  # Complete POS Database Setup
  
  This SQL file contains the complete database schema for the POS application including:
  
  1. Authentication Setup
     - User profiles with role-based access
     - Automatic profile creation trigger
     - User deletion function
  
  2. Product Management
     - Products with multi-unit support
     - Categories
     - Product units with conversion factors
  
  3. Sales System
     - Sales transactions with multiple payment methods
     - Sale items with discount support
     - Invoice status tracking
  
  4. Inventory Management
     - Stock movements tracking
     - Automatic stock updates with unit conversion
  
  5. Settings Management
     - Store configuration
     - Receipt customization
  
  6. Security
     - Row Level Security (RLS) on all tables
     - Role-based permissions
     - Secure functions
  
  7. Sample Data
     - Default categories
     - Sample products
     - Default settings
*/

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types
CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');
CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');

-- Create users table (extends Supabase auth.users)
CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz DEFAULT now()
);

-- Create profiles table
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role user_role DEFAULT 'cashier' NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Create categories table
CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES users(id)
);

-- Create products table
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
  created_by uuid REFERENCES users(id),
  base_unit text DEFAULT 'pcs',
  pcs_per_base_unit integer DEFAULT 1 NOT NULL,
  price_per_pcs numeric(12,2) DEFAULT 0 NOT NULL,
  stock_pcs integer DEFAULT 0 NOT NULL
);

-- Create product_units table
CREATE TABLE IF NOT EXISTS product_units (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id uuid REFERENCES products(id) ON DELETE CASCADE,
  unit_name text NOT NULL,
  conversion_factor numeric(12,4) DEFAULT 1 NOT NULL,
  is_base_unit boolean DEFAULT false,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES users(id),
  UNIQUE(product_id, unit_name)
);

-- Create sales table
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
  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
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
  created_by uuid REFERENCES users(id),
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
  updated_by uuid REFERENCES users(id)
);

-- Create indexes for better performance
CREATE INDEX IF NOT EXISTS idx_products_base_unit ON products(base_unit);
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice_status ON sales(invoice_status);
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_id ON sale_items(unit_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_unit_type ON sale_items(unit_type);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_id ON stock_movements(unit_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_unit_type ON stock_movements(unit_type);
CREATE INDEX IF NOT EXISTS idx_product_units_product_id ON product_units(product_id);
CREATE INDEX IF NOT EXISTS idx_product_units_is_base_unit ON product_units(product_id, is_base_unit);

-- Enable Row Level Security
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- Create helper function to get user role
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

-- Create function to handle new user registration
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO users (id) VALUES (NEW.id);
  INSERT INTO profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'cashier'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger for new user registration
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- Create function to delete user completely
CREATE OR REPLACE FUNCTION delete_user(user_id uuid)
RETURNS void AS $$
BEGIN
  -- Delete from auth.users (this will cascade to other tables)
  DELETE FROM auth.users WHERE id = user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create function to generate sale numbers
CREATE OR REPLACE FUNCTION generate_sale_number()
RETURNS text AS $$
DECLARE
  today_date text;
  sequence_num integer;
  sale_number text;
BEGIN
  today_date := to_char(now(), 'YYYYMMDD');
  
  -- Get the next sequence number for today
  SELECT COALESCE(MAX(CAST(SUBSTRING(sale_number FROM 14) AS integer)), 0) + 1
  INTO sequence_num
  FROM sales
  WHERE sale_number LIKE 'SALE-' || today_date || '-%';
  
  sale_number := 'SALE-' || today_date || '-' || LPAD(sequence_num::text, 4, '0');
  
  RETURN sale_number;
END;
$$ LANGUAGE plpgsql;

-- Create function to update product stock with units
CREATE OR REPLACE FUNCTION update_product_stock_with_units()
RETURNS trigger AS $$
DECLARE
  pcs_quantity integer;
  base_unit_quantity numeric;
  current_pcs_per_base_unit integer;
BEGIN
  -- Get the current pcs_per_base_unit for the product
  SELECT pcs_per_base_unit INTO current_pcs_per_base_unit
  FROM products
  WHERE id = NEW.product_id;
  
  -- Convert quantity to pieces based on unit_type
  IF NEW.unit_type = 'pcs' THEN
    pcs_quantity := NEW.quantity;
  ELSE
    -- For base_unit, multiply by pcs_per_base_unit
    pcs_quantity := NEW.quantity * current_pcs_per_base_unit;
  END IF;
  
  -- Calculate base unit quantity
  base_unit_quantity := pcs_quantity::numeric / current_pcs_per_base_unit;
  
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

-- Create trigger for stock updates
DROP TRIGGER IF EXISTS update_product_stock_trigger ON stock_movements;
CREATE TRIGGER update_product_stock_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock_with_units();

-- RLS Policies for users table
CREATE POLICY "Users can view their own data" ON users
  FOR SELECT TO authenticated
  USING (auth.uid() = id);

CREATE POLICY "Users can update their own data" ON users
  FOR UPDATE TO authenticated
  USING (auth.uid() = id);

-- RLS Policies for profiles table
CREATE POLICY "Users can view their own profile" ON profiles
  FOR SELECT TO public
  USING (auth.uid() = id);

CREATE POLICY "Admins can view all profiles" ON profiles
  FOR SELECT TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Users can update their own profile" ON profiles
  FOR UPDATE TO public
  USING (auth.uid() = id);

CREATE POLICY "Admins can update all profiles" ON profiles
  FOR UPDATE TO public
  USING (get_user_role(auth.uid()) = 'admin');

CREATE POLICY "Admins can insert profiles" ON profiles
  FOR INSERT TO public
  WITH CHECK (get_user_role(auth.uid()) = 'admin');

-- RLS Policies for categories table
CREATE POLICY "All authenticated users can view categories" ON categories
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage categories" ON categories
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin', 'stockist']));

-- RLS Policies for products table
CREATE POLICY "All authenticated users can view products" ON products
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage products" ON products
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin', 'stockist']));

-- RLS Policies for product_units table
CREATE POLICY "All authenticated users can view product units" ON product_units
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage product units" ON product_units
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin', 'stockist']));

-- RLS Policies for sales table
CREATE POLICY "All authenticated users can view sales" ON sales
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create sales" ON sales
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins can manage all sales" ON sales
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- RLS Policies for sale_items table
CREATE POLICY "Users can view sale items" ON sale_items
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Users can create sale items" ON sale_items
  FOR INSERT TO authenticated
  WITH CHECK (true);

CREATE POLICY "Admins can manage sale items" ON sale_items
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- RLS Policies for stock_movements table
CREATE POLICY "All authenticated users can view stock movements" ON stock_movements
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "All authenticated users can create stock movements" ON stock_movements
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = created_by);

CREATE POLICY "Admins, stockists, and cashiers can update stock movements" ON stock_movements
  FOR UPDATE TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin', 'stockist', 'cashier']));

CREATE POLICY "Admins, stockists, and cashiers can delete stock movements" ON stock_movements
  FOR DELETE TO public
  USING (get_user_role(auth.uid()) = ANY(ARRAY['admin', 'stockist', 'cashier']));

-- RLS Policies for settings table
CREATE POLICY "All authenticated users can view settings" ON settings
  FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admins can manage settings" ON settings
  FOR ALL TO public
  USING (get_user_role(auth.uid()) = 'admin');

-- Insert default categories
INSERT INTO categories (name, description) VALUES
  ('Electronics', 'Electronic devices and accessories'),
  ('Clothing', 'Apparel and fashion items'),
  ('Food & Beverage', 'Food and drink products'),
  ('Home & Garden', 'Home improvement and gardening supplies'),
  ('Books & Media', 'Books, magazines, and media content'),
  ('Sports & Outdoors', 'Sports equipment and outdoor gear'),
  ('Health & Beauty', 'Health and beauty products'),
  ('Toys & Games', 'Toys and gaming products')
ON CONFLICT (name) DO NOTHING;

-- Insert sample products with multi-unit support
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
    ('T-Shirt Cotton Basic', 'SHIRT-001', clothing_id, 150000, 25000, 20000, 10, 60, 'dus', 6, 'Basic cotton t-shirt, various sizes'),
    ('Instant Noodles', 'NOODLE-001', food_id, 120000, 5000, 4000, 20, 480, 'dus', 24, 'Instant noodles pack'),
    ('Wireless Mouse', 'MOUSE-001', electronics_id, 250000, 250000, 200000, 8, 8, 'pcs', 1, 'Wireless optical mouse'),
    ('Mineral Water', 'WATER-001', food_id, 48000, 2000, 1500, 15, 360, 'dus', 24, 'Mineral water 600ml bottles')
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
  ('print_receipt_auto', 'true', 'Auto-print receipt after sale'),
  ('company_logo', '', 'Company logo URL for receipts')
ON CONFLICT (key) DO NOTHING;

-- Create storage bucket for company assets (if not exists)
INSERT INTO storage.buckets (id, name, public)
VALUES ('company-assets', 'company-assets', true)
ON CONFLICT (id) DO NOTHING;

-- Set up storage policies for company assets
CREATE POLICY "Public can view company assets" ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'company-assets');

CREATE POLICY "Authenticated users can upload company assets" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'company-assets');

CREATE POLICY "Admins can manage company assets" ON storage.objects
  FOR ALL TO public
  USING (bucket_id = 'company-assets' AND get_user_role(auth.uid()) = 'admin');

-- Disable email confirmation for easier testing
UPDATE auth.config 
SET email_confirm = false 
WHERE true;

-- Create a default admin user (optional - for initial setup)
-- Note: You should change this email and password after setup
DO $$
BEGIN
  -- This will only work if you run it manually and provide actual credentials
  -- INSERT INTO auth.users (email, encrypted_password, email_confirmed_at, created_at, updated_at)
  -- VALUES ('admin@awanvisual.com', crypt('admin123', gen_salt('bf')), now(), now(), now());
  
  -- The above is commented out for security - create admin user through the app instead
END $$;

-- Final verification queries (optional - for testing)
-- SELECT 'Database setup completed successfully!' as status;
-- SELECT table_name, is_insertable_into FROM information_schema.tables WHERE table_schema = 'public';
-- SELECT schemaname, tablename, policyname FROM pg_policies WHERE schemaname = 'public';