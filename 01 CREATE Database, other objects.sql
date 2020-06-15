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

IF (NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'Obfuscator')) 
BEGIN
    EXEC ('CREATE SCHEMA [Obfuscator] AUTHORIZATION [dbo]')
END
GO

--Table type for a various "string" data entity (gender, suffix, etc.)
DROP TYPE IF EXISTS dbo.DataEntity;
CREATE TYPE dbo.DataEntity AS TABLE
(
    [Value] NVARCHAR(256) NULL
);
GO
