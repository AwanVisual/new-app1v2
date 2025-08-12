@@ .. @@
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

 -- Function to handle new user registration
 CREATE OR REPLACE FUNCTION handle_new_user()
 RETURNS trigger AS $$
 BEGIN
   INSERT INTO profiles (id, full_name, role)
-  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', 'User'), 'cashier');
+  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', 'User'), 'cashier'::user_role);
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