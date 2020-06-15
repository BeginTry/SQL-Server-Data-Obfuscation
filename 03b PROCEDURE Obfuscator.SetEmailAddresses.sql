USE MLtools;
GO

CREATE OR ALTER PROCEDURE Obfuscator.SetEmailAddresses
	@DatabaseName SYSNAME,
	@TableSchema SYSNAME,
	@TableName SYSNAME,
	@EmailAddressColumn SYSNAME,
	@DisableTriggers BIT = 1
/******************************************************************************
* Name     : Obfuscate.EmailAddresses
* Purpose  : Randomly overwrites existing email address data with fake email addresses.
* Inputs   : @DatabaseName, @TableSchema, @TableName - 3-part name of the table.
*			 @EmailAddressColumn - column name that holds the email address data.
*			 @DisableTriggers - self-explanatory.
* Outputs  : none
* Returns  : 3-part name of the table and the number of email addresses obfuscated.
******************************************************************************
* Change History
*	03/19/2020	DMason	Created.
******************************************************************************/
AS
BEGIN

DECLARE @Msg NVARCHAR(2047);
DECLARE @TSql NVARCHAR(MAX);

--Verify DB exists.
IF DB_ID(@DatabaseName) IS NULL
BEGIN
	SET @Msg = 'Database does not exist: ' + QUOTENAME(@DatabaseName);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END
--Verify schema/object exists.
ELSE IF OBJECT_ID(QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName)) IS NULL
BEGIN
	SET @Msg = 'Table (or schema) does not exist: ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END

--Verify object is a user table.
SET @TSql = 'USE ' + QUOTENAME(@DatabaseName) + ';
DECLARE @i INT;
SELECT TOP(1) @i = 1
FROM sys.objects o
WHERE SCHEMA_NAME(o.schema_id) = ''' + @TableSchema + '''
AND o.name = ''' + @TableName + '''
AND o.type <> ''U'' ';
EXEC(@TSql);

IF @@ROWCOUNT = 1
BEGIN
	SET @Msg = 'Object is not a user table: ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END

--Verify column exists in table, determine its max size and data type.
DECLARE @CharMaxLength INT;
DECLARE @DataType SYSNAME;
SET @TSql = 'SELECT @Length = CHARACTER_MAXIMUM_LENGTH, @Type = DATA_TYPE
FROM ' + QUOTENAME(@DatabaseName) + '.INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = ''' + @TableSchema + '''
AND c.TABLE_NAME = ''' + @TableName + '''
AND c.COLUMN_NAME = ''' + @EmailAddressColumn + '''
';

EXECUTE sp_executesql 
    @TSql, 
    N'@Length INT OUTPUT, @Type SYSNAME OUTPUT', 
    @CharMaxLength OUTPUT, @DataType OUTPUT;
--SELECT @CharMaxLength, @DataType;

IF @DataType IS NULL
BEGIN
	SET @Msg = 'Column does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@EmailAddressColumn);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END

IF @DataType NOT IN ('nchar', 'nvarchar', 'char', 'varchar')
BEGIN
	SET @Msg = 'Column data type does not support email addresses: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@EmailAddressColumn) + ' (' + @DataType + ')';
	RAISERROR(@Msg, 16, 1);
	RETURN;
END


--	1.	Get source table counts of email value types:
--		NULL vs Zero-length string vs Multi-char string.
DECLARE @NullCount BIGINT;
DECLARE @EmptyStringCount BIGINT;
DECLARE @ValueCount BIGINT;
DECLARE @TotalCount BIGINT;

SET @TSql = N'SELECT
	@Count1 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@EmailAddressColumn) + ' IS NULL THEN 1 ELSE 0 END AS BIGINT)),
	@Count2 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@EmailAddressColumn) + ' = '''' THEN 1 ELSE 0 END AS BIGINT)),
	@Count3 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@EmailAddressColumn) + ' <> '''' THEN 1 ELSE 0 END AS BIGINT)),
	@Count4 = COUNT_BIG(*)
FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' t;';
EXEC SP_EXECUTESQL 
	@Query  = @TSql,
	@Params = N'@Count1 BIGINT OUTPUT, @Count2 BIGINT OUTPUT, @Count3 BIGINT OUTPUT, @Count4 BIGINT OUTPUT',
	@Count1 = @NullCount OUTPUT,
	@Count2 = @EmptyStringCount OUTPUT,
	@Count3 = @ValueCount OUTPUT,
	@Count4 = @TotalCount OUTPUT


IF @TotalCount = 0
BEGIN
	SELECT @Msg = 'Table does not contain any rows: ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 10, 1);
	RETURN;
END


--	2.	Populate a #temp table with fake email addresses--1 for every row in the source table.
DROP TABLE IF EXISTS #FakeData;
CREATE TABLE #FakeData (
	ID BIGINT IDENTITY PRIMARY KEY,
	EmailAddress NVARCHAR(255)
)

--Equivalent number of fake email adddresses.
INSERT INTO #FakeData EXEC Generator.GetEmailAddresses
	@Count = @ValueCount;

--Equivalent number of NULL email adddresses.
INSERT INTO #FakeData (EmailAddress)
SELECT TOP(@NullCount) NULL
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3

--Equivalent number of empty string email adddresses.
INSERT INTO #FakeData (EmailAddress)
SELECT TOP(@EmptyStringCount) ''
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3


--	3.	Update the source table with fake email addresses from the #temp table.

IF @DisableTriggers = 1
BEGIN
	--Disable all triggers on source table.
	SET @TSql = '
	USE ' + QUOTENAME(@DatabaseName) + ';
	DISABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';'
	EXEC(@TSql);
END

--Will need this to prevent "String or binary data would be truncated" errors.
--	@CharMaxLength

--UPDATE
SET @TSql = '
;WITH SourceTable AS
(
	SELECT
		ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VirtualID, *
	FROM
	(
		SELECT TOP (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ') 
			source.' + QUOTENAME(@EmailAddressColumn) + '
		FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' source
		ORDER BY NEWID()
	) a
)
UPDATE st SET
	st.' + QUOTENAME(@EmailAddressColumn) + ' = ' + CASE WHEN @CharMaxLength = -1 THEN 'fake.EmailAddress' ELSE 'LEFT(fake.EmailAddress, ' + CAST(@CharMaxLength AS NVARCHAR(MAX)) + ')' END + '
FROM SourceTable st
JOIN #FakeData fake
	ON fake.ID = st.VirtualID
'
EXEC(@TSql);

SELECT @DatabaseName AS DatabaseName,
	@TableSchema AS TableSchema,
	@TableName AS TableName,
	@EmailAddressColumn AS ColumnName,
	@@ROWCOUNT AS [Number of EmailAddresses obfuscated];

IF @DisableTriggers = 1
BEGIN
	--Enable all triggers on source table.
	SET @TSql = '
	USE ' + QUOTENAME(@DatabaseName) + ';
	ENABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';'
	EXEC(@TSql);
END

END
GO
