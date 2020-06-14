IF DB_ID('MLtools') IS NULL
	EXEC('CREATE DATABASE MLtools');
GO

USE MLtools;
GO

IF (NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Generator')) 
BEGIN
    EXEC ('CREATE SCHEMA [Generator] AUTHORIZATION [dbo]')
END
GO

IF (NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Obfuscate')) 
BEGIN
    EXEC ('CREATE SCHEMA [Obfuscate] AUTHORIZATION [dbo]')
END
GO

--Table type for unique INT IDs.
DROP TYPE IF EXISTS dbo.UniqueID;
--CREATE TYPE dbo.UniqueID AS TABLE
--(
--	ID BIGINT PRIMARY KEY
--);


--Table type for a various "string" data entity (gender, suffix, etc.)
DROP TYPE IF EXISTS dbo.DataEntity;
CREATE TYPE dbo.DataEntity AS TABLE
(
    [Value] NVARCHAR(256) NULL
);


