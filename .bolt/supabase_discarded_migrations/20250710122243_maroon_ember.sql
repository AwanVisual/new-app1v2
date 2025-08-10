/*
  # Create Triggers

  1. Triggers
    - `stock_movement_trigger` - Update product stock when stock movement is inserted
    - `on_auth_user_created` - Create profile when new user is created

  2. Security
    - Triggers ensure data consistency
    - Automatic profile creation for new users
    - Automatic stock updates
*/

-- Trigger to update product stock on stock movement
CREATE TRIGGER stock_movement_trigger
  AFTER INSERT ON stock_movements
  FOR EACH ROW
  EXECUTE FUNCTION update_product_stock();

-- Trigger to create profile for new users
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();