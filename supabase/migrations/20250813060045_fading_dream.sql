/*
  # Add foreign key relationship between stock_movements and profiles

  1. Database Changes
    - Add foreign key constraint linking stock_movements.created_by to profiles.id
    - This enables Supabase to resolve joins between these tables

  2. Security
    - No RLS changes needed as existing policies remain intact

  3. Notes
    - This fixes the PostgREST error when querying stock_movements with profiles(full_name)
    - Enables proper user tracking in stock movement history
*/

-- Add foreign key constraint between stock_movements and profiles
ALTER TABLE public.stock_movements
ADD CONSTRAINT IF NOT EXISTS fk_stock_movements_created_by_profiles
FOREIGN KEY (created_by)
REFERENCES public.profiles(id)
ON DELETE SET NULL;