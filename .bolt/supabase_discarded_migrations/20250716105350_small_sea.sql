/*
  # Complete Database Migration SQL
  
  This file contains the complete database structure for the POS system including:
  1. Custom Types (Enums)
  2. Tables with all constraints
  3. Indexes for performance
  4. Row Level Security (RLS) policies
  5. Functions and triggers
  6. Sample data (optional)
  
  Usage:
  1. Create a new Supabase project or PostgreSQL database
  2. Run this SQL file to create the complete structure
  3. The system will be ready to use
*/

-- =============================================
-- 1. CREATE CUSTOM TYPES (ENUMS)
-- =============================================

CREATE TYPE user_role AS ENUM ('admin', 'cashier', 'stockist');
CREATE TYPE payment_method AS ENUM ('cash', 'card', 'transfer', 'credit');
CREATE TYPE transaction_type AS ENUM ('inbound', 'outbound', 'adjustment');
CREATE TYPE invoice_status AS ENUM ('lunas', 'dp', 'belum_bayar');

-- =============================================
-- 2. CREATE TABLES
-- =============================================

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
  cost numeric(12,2) DEFAULT 0,
  stock_quantity integer DEFAULT 0,
  min_stock_level integer DEFAULT 10,
  description text,
  image_url text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

-- Profiles table (extends auth.users)
CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL,
  role user_role DEFAULT 'cashier',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Sales table
CREATE TABLE IF NOT EXISTS sales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_number text UNIQUE NOT NULL,
  customer_name text,
  subtotal numeric(12,2) NOT NULL,
  tax_amount numeric(12,2) DEFAULT 0,
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

-- Sale items table
CREATE TABLE IF NOT EXISTS sale_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  sale_id uuid REFERENCES sales(id) ON DELETE CASCADE,
  product_id uuid REFERENCES products(id),
  quantity integer NOT NULL,
  unit_price numeric(12,2) NOT NULL,
  subtotal numeric(12,2) NOT NULL,
  discount numeric(10,2) DEFAULT 0,
  created_at timestamptz DEFAULT now()
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
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
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

-- =============================================
-- 3. CREATE INDEXES FOR PERFORMANCE
-- =============================================

-- Products indexes
CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active);
CREATE INDEX IF NOT EXISTS idx_products_stock_quantity ON products(stock_quantity);

-- Sales indexes
CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at);
CREATE INDEX IF NOT EXISTS idx_sales_cashier_id ON sales(cashier_id);
CREATE INDEX IF NOT EXISTS idx_sales_invoice_status ON sales(invoice_status);
CREATE INDEX IF NOT EXISTS idx_sales_payment_method ON sales(payment_method);

-- Sale items indexes
CREATE INDEX IF NOT EXISTS idx_sale_items_sale_id ON sale_items(sale_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_product_id ON sale_items(product_id);
CREATE INDEX IF NOT EXISTS idx_sale_items_discount ON sale_items(discount);

-- Stock movements indexes
CREATE INDEX IF NOT EXISTS idx_stock_movements_product_id ON stock_movements(product_id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created_at ON stock_movements(created_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_transaction_type ON stock_movements(transaction_type);

-- Settings indexes
CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);

-- =============================================
-- 4. CREATE FUNCTIONS
-- =============================================

-- Function to generate sale numbers
CREATE OR REPLACE FUNCTION generate_sale_number()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  sale_date text;
  sequence_num text;
BEGIN
  sale_date := to_char(now(), 'YYYYMMDD');
  
  SELECT LPAD((COUNT(*) + 1)::text, 4, '0')
  INTO sequence_num
  FROM sales
  WHERE DATE(created_at) = CURRENT_DATE;
  
  RETURN 'SALE-' || sale_date || '-' || sequence_num;
END;
$$;

-- Function to get user role
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

-- Function to update product stock
CREATE OR REPLACE FUNCTION update_product_stock()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.transaction_type = 'inbound' THEN
    UPDATE products 
    SET stock_quantity = stock_quantity + NEW.quantity,
        updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'outbound' THEN
    UPDATE products 
    SET stock_quantity = stock_quantity - NEW.quantity,
        updated_at = now()
    WHERE id = NEW.product_id;
  ELSIF NEW.transaction_type = 'adjustment' THEN
    UPDATE products 
    SET stock_quantity = NEW.quantity,
        updated_at = now()
    WHERE id = NEW.product_id;
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
  INSERT INTO profiles (id, full_name, role)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email),
    'cashier'::user_role
  );
  RETURN NEW;
END;
$$;

-- =============================================
-- 5. CREATE TRIGGERS
-- =============================================

-- Trigger for stock movements
CREATE TRIGGER stock_movement_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock();

-- Trigger for new user registration
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();

-- =============================================
-- 6. ENABLE ROW LEVEL SECURITY (RLS)
-- =============================================

-- Enable RLS on all tables
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE sales ENABLE ROW LEVEL SECURITY;
ALTER TABLE sale_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- =============================================
-- 7. CREATE RLS POLICIES
-- =============================================

-- Categories policies
CREATE POLICY "All authenticated users can view categories"
  ON categories FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage categories"
  ON categories FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Products policies
CREATE POLICY "All authenticated users can view products"
  ON products FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage products"
  ON products FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));

-- Profiles policies
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
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

CREATE POLICY "Admins can update all profiles"
  ON profiles FOR UPDATE
  TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

CREATE POLICY "Admins can insert profiles"
  ON profiles FOR INSERT
  TO public
  WITH CHECK (get_user_role(auth.uid()) = 'admin'::user_role);

-- Sales policies
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
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

-- Sale items policies
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
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

-- Stock movements policies
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
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

CREATE POLICY "Admins, stockists, and cashiers can delete stock movements"
  ON stock_movements FOR DELETE
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role, 'cashier'::user_role]));

-- Settings policies
CREATE POLICY "All authenticated users can view settings"
  ON settings FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins can manage settings"
  ON settings FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = 'admin'::user_role);

-- =============================================
-- 8. INSERT DEFAULT SETTINGS (OPTIONAL)
-- =============================================

INSERT INTO settings (key, value, description) VALUES
('store_name', 'Awanvisual POS Demo', 'Name of the store'),
('store_address', 'Jl. Demo No. 123, Jakarta', 'Store address'),
('store_phone', '+62 21 1234567', 'Store phone number'),
('store_email', 'demo@awanvisual.com', 'Store email address'),
('store_website', 'www.awanvisual.com', 'Store website'),
('receipt_header', 'Terima kasih telah berbelanja!', 'Receipt header message'),
('receipt_footer', 'Barang yang sudah dibeli tidak dapat dikembalikan', 'Receipt footer message'),
('payment_note_line1', 'Transfer BCA: 1234567890 / AWANVISUAL', 'Payment note line 1'),
('payment_note_line2', 'Konfirmasi transfer ke WhatsApp: 08123456789', 'Payment note line 2'),
('low_stock_threshold', '10', 'Low stock alert threshold'),
('low_stock_alerts', 'true', 'Enable low stock alerts'),
('daily_sales_summary', 'false', 'Enable daily sales summary'),
('print_receipt_auto', 'true', 'Auto print receipt after sale')
ON CONFLICT (key) DO NOTHING;

-- =============================================
-- 9. INSERT SAMPLE DATA (OPTIONAL)
-- =============================================

-- Sample categories
INSERT INTO categories (name, description) VALUES
('Elektronik', 'Peralatan elektronik'),
('Makanan', 'Makanan dan minuman'),
('Pakaian', 'Pakaian dan aksesoris'),
('Alat Tulis', 'Peralatan tulis dan kantor')
ON CONFLICT (name) DO NOTHING;

-- Sample products (you can uncomment this if you want sample data)
/*
INSERT INTO products (name, sku, price, cost, stock_quantity, min_stock_level, description, category_id) 
SELECT 
  'Laptop Gaming', 'LAPTOP-001', 15000000, 12000000, 5, 2, 'Laptop gaming high performance',
  (SELECT id FROM categories WHERE name = 'Elektronik' LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM products WHERE sku = 'LAPTOP-001');

INSERT INTO products (name, sku, price, cost, stock_quantity, min_stock_level, description, category_id)
SELECT 
  'Mouse Wireless', 'MOUSE-001', 150000, 100000, 20, 5, 'Mouse wireless ergonomis',
  (SELECT id FROM categories WHERE name = 'Elektronik' LIMIT 1)
WHERE NOT EXISTS (SELECT 1 FROM products WHERE sku = 'MOUSE-001');
*/

-- =============================================
-- MIGRATION COMPLETE
-- =============================================

-- Display completion message
DO $$
BEGIN
  RAISE NOTICE 'Database migration completed successfully!';
  RAISE NOTICE 'Tables created: categories, products, profiles, sales, sale_items, stock_movements, settings';
  RAISE NOTICE 'Functions created: generate_sale_number, get_user_role, update_product_stock, handle_new_user';
  RAISE NOTICE 'Triggers created: stock_movement_trigger, on_auth_user_created';
  RAISE NOTICE 'RLS policies applied to all tables';
  RAISE NOTICE 'Default settings inserted';
  RAISE NOTICE 'System is ready to use!';
END $$;