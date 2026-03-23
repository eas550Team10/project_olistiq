-- Giving the Role Based Access Control (RBAC)

-- 1. Creating the roles - As per the requirement - Two roles 
CREATE ROLE olist_analyst;
CREATE ROLE olist_app_user;

-- 2. Now giving the access
GRANT USAGE ON SCHEMA public to olist_analyst;
GRANT USAGE ON SCHEMA public to olist_app_user;

-- 3. Providing Read only access to Analyst 
GRANT SELECT ON ALL TABLES IN SCHEMA public TO olist_analyst;


ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO olist_analyst;

-- 4. App user -> Read + Write 
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO olist_app_user;

ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE ON TABLES TO olist_app_user;

-- 5. Create Users (Login Roles)

CREATE USER analyst_user WITH PASSWORD 'Analyst@EAS550';
CREATE USER app_user WITH PASSWORD 'AppUser@EAS550';

-- 6. Assign roles 
GRANT olist_analyst TO analyst_user;
GRANT olist_app_user TO app_user;

-- 7. Optional : restrict dangerous actions 
REVOKE DELETE ON ALL TABLES IN SCHEMA public FROM olist_app_user;
