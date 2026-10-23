-- Everything the app owns lives in the app schema. The app's SQL user gets
-- read/write on this schema only, through the app_rw role
-- (db/migrate.mjs adds the app's managed identity to it).
CREATE SCHEMA app;
GO

CREATE ROLE app_rw;
GO

GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON SCHEMA::app TO app_rw;
GO
