/*
  # Create Categories Table

  1. New Tables
    - `categories`
      - `id` (uuid, primary key)
      - `name` (text, unique, required)
      - `description` (text, optional)
      - `created_at` (timestamp)
      - `created_by` (uuid, references auth.users)

  2. Security
    - Enable RLS on `categories` table
    - All authenticated users can view categories
    - Admins and stockists can manage categories
*/

CREATE TABLE IF NOT EXISTS categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE NOT NULL,
  description text,
  created_at timestamptz DEFAULT now(),
  created_by uuid REFERENCES auth.users(id)
);

ALTER TABLE categories ENABLE ROW LEVEL SECURITY;

-- Policies for categories
CREATE POLICY "All authenticated users can view categories"
  ON categories
  FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admins and stockists can manage categories"
  ON categories
  FOR ALL
  TO public
  USING (get_user_role(auth.uid()) = ANY (ARRAY['admin'::user_role, 'stockist'::user_role]));