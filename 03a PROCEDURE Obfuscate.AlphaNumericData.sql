USE MLtools;
GO

CREATE OR ALTER PROCEDURE Obfuscate.AlphaNumericData
	@DatabaseName SYSNAME,
	@TableSchema SYSNAME,
	@TableName SYSNAME,
	@AlphaNumericColumn SYSNAME,
	@DisableTriggers BIT = 1
/******************************************************************************
* Name     : Obfuscate.AlphaNumericData
* Purpose  : Randomly overwrites existing Alpha-Numeric data with fake Alpha-Numeric data.
* Inputs   : @DatabaseName, @TableSchema, @TableName - 3-part name of the table.
*			 @AlphaNumericColumn - column name that holds the Alpha-Numeric data.
*			 @DisableTriggers - self-explanatory.
* Outputs  : none
* Returns  : 3-part name of the table and the number of items obfuscated.
******************************************************************************
* Change History
*	03/30/2020	DMason	Created.
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
AND c.COLUMN_NAME = ''' + @AlphaNumericColumn + '''
';

EXECUTE sp_executesql 
    @TSql, 
    N'@Length INT OUTPUT, @Type SYSNAME OUTPUT', 
    @CharMaxLength OUTPUT, @DataType OUTPUT;
--SELECT @CharMaxLength, @DataType;

IF @DataType IS NULL
BEGIN
	SET @Msg = 'Column does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@AlphaNumericColumn);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END

IF @DataType NOT IN ('nchar', 'nvarchar', 'char', 'varchar')
BEGIN
	SET @Msg = 'Column data type does not support Alpha-Numerices: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@AlphaNumericColumn) + ' (' + @DataType + ')';
	RAISERROR(@Msg, 16, 1);
	RETURN;
END


--	1.	Get source table counts of alphanumeric data values value types:
--		NULL vs Zero-length string vs Multi-char string.
DECLARE @NullCount BIGINT;
DECLARE @EmptyStringCount BIGINT;
DECLARE @ValueCount BIGINT;
DECLARE @TotalCount BIGINT;

SET @TSql = N'SELECT
	@Count1 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@AlphaNumericColumn) + ' IS NULL THEN 1 ELSE 0 END AS BIGINT)),
	@Count2 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@AlphaNumericColumn) + ' = '''' THEN 1 ELSE 0 END AS BIGINT)),
	@Count3 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@AlphaNumericColumn) + ' <> '''' THEN 1 ELSE 0 END AS BIGINT)),
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


--	2.	Populate a #temp table with fake alphanumeric data values--1 for every row in the source table.
DECLARE @AlphaNumericData AS dbo.DataEntity;
SET @TSql = 'SELECT ' + QUOTENAME(@AlphaNumericColumn) + ' 
	FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '
	WHERE ' + QUOTENAME(@AlphaNumericColumn) + ' <> '''';';
INSERT INTO @AlphaNumericData EXEC(@TSql);

DROP TABLE IF EXISTS #FakeData;
CREATE TABLE #FakeData (
	ID BIGINT IDENTITY(1,1) PRIMARY KEY,
	AlphaNumericData NVARCHAR(255)
)

--Equivalent number of fake alphanumeric data values.
INSERT INTO #FakeData EXEC Generator.GetAlphaNumericData @AlphaNumericData;
DELETE FROM @AlphaNumericData;	--No longer needed.

--Equivalent number of NULL alphanumeric data values adddresses.
INSERT INTO #FakeData (AlphaNumericData)
SELECT TOP(@NullCount) NULL
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3

--Equivalent number of empty string alphanumeric data values.
INSERT INTO #FakeData (AlphaNumericData)
SELECT TOP(@EmptyStringCount) ''
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3


--	3.	Update the source table with fake AlphaNumericDatas from the #temp table.

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
			source.' + QUOTENAME(@AlphaNumericColumn) + '
		FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' source
		ORDER BY NEWID()
	) a
)
UPDATE st SET
	st.' + QUOTENAME(@AlphaNumericColumn) + ' = ' + CASE WHEN @CharMaxLength = -1 THEN 'fake.AlphaNumericData' ELSE 'LEFT(fake.AlphaNumericData, ' + CAST(@CharMaxLength AS NVARCHAR(MAX)) + ')' END + '
FROM SourceTable st
JOIN #FakeData fake
	ON fake.ID = st.VirtualID
'
EXEC(@TSql);

SELECT @DatabaseName AS DatabaseName,
	@TableSchema AS TableSchema,
	@TableName AS TableName,
	@AlphaNumericColumn AS ColumnName,
	@@ROWCOUNT AS [Number of AlphaNumeric items obfuscated];


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
