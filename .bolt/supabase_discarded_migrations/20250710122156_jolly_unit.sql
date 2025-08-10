/*
  # Create Products Table

  1. New Tables
    - `products`
      - `id` (uuid, primary key)
      - `name` (text, required)
      - `sku` (text, unique, required)
      - `category_id` (uuid, references categories)
      - `price` (numeric, required)
      - `cost` (numeric, default 0)
      - `stock_quantity` (integer, default 0)
      - `min_stock_level` (integer, default 10)
      - `description` (text, optional)
      - `image_url` (text, optional)
      - `is_active` (boolean, default true)
      - `created_at` (timestamp)
      - `updated_at` (timestamp)
      - `created_by` (uuid, references auth.users)

  2. Security
    - Enable RLS on `products` table
    - All authenticated users can view products
    - Admins and stockists can manage products
*/

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
  created_by uuid REFERENCES auth.users(id)
);

ALTER TABLE products ENABLE ROW LEVEL SECURITY;

-- Policies for products
CREATE POLICY "All authenticated users can view products"
  ON products
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage products"
  ON products
  FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));