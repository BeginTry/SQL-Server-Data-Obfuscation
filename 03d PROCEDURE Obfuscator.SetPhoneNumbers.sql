USE MLtools;
GO

CREATE OR ALTER PROCEDURE Obfuscator.SetPhoneNumbers
	@DatabaseName SYSNAME,
	@TableSchema SYSNAME,
	@TableName SYSNAME,
	@PhoneNumColumn SYSNAME,
	@DisableTriggers BIT = 1
/******************************************************************************
* Name     : Obfuscate.PhoneNumbers
* Purpose  : Randomly overwrites existing phone number data with fake phone numbers.
* Inputs   : @DatabaseName, @TableSchema, @TableName - 3-part name of the table.
*			 @PhoneNumColumn - column name that holds the phone number data.
*			 @DisableTriggers - self-explanatory.
* Outputs  : none
* Returns  : 3-part name of the table and the number of phone numbers obfuscated.
******************************************************************************
* Change History
*	03/19/2020	DMason	Created.
*	10/08/2020	DMason	Fix bug involving NULL value.
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
AND c.COLUMN_NAME = ''' + @PhoneNumColumn + '''
';

EXECUTE sp_executesql 
    @TSql, 
    N'@Length INT OUTPUT, @Type SYSNAME OUTPUT', 
    @CharMaxLength OUTPUT, @DataType OUTPUT;
--SELECT @CharMaxLength, @DataType;

IF @DataType IS NULL
BEGIN
	SET @Msg = 'Column does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@PhoneNumColumn);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END

IF @DataType NOT IN ('nchar', 'nvarchar', 'char', 'varchar')
BEGIN
	SET @Msg = 'Column data type does not support phone number data: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@PhoneNumColumn) + ' (' + @DataType + ')';
	RAISERROR(@Msg, 16, 1);
	RETURN;
END


--	1.	Get source table counts of phone number value types:
--		NULL vs Zero-length string vs Multi-char string.
DECLARE @NullCount BIGINT;
DECLARE @EmptyStringCount BIGINT;
DECLARE @ValueCount BIGINT;
DECLARE @TotalCount BIGINT;

SET @TSql = N'SELECT
	@Count1 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@PhoneNumColumn) + ' IS NULL THEN 1 ELSE 0 END AS BIGINT)),
	@Count2 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@PhoneNumColumn) + ' = '''' THEN 1 ELSE 0 END AS BIGINT)),
	@Count3 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@PhoneNumColumn) + ' <> '''' THEN 1 ELSE 0 END AS BIGINT)),
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

--	2.	Populate a #temp table with fake phone numbers--1 for every row in the source table.
DROP TABLE IF EXISTS #FakeData;
CREATE TABLE #FakeData (
	PhoneNum NVARCHAR(255)
)

--Equivalent number of fake phone numbers.
INSERT INTO #FakeData EXEC Generator.GetPhoneNumbers
	@Count = @ValueCount;

--Equivalent number of NULL phone numbers.
INSERT INTO #FakeData (PhoneNum)
SELECT TOP(@NullCount) NULL
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3

--Equivalent number of empty string phone numbers.
INSERT INTO #FakeData (PhoneNum)
SELECT TOP(@EmptyStringCount) ''
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3

ALTER TABLE #FakeData ADD DigitsOnly NVARCHAR(255);
UPDATE #FakeData SET DigitsOnly = (SUBSTRING(PhoneNum, 2, 3) + SUBSTRING(PhoneNum, 7, 3) + SUBSTRING(PhoneNum, 11, 4))
WHERE PhoneNum <> '';

--Account for any "empty string" values not explicitly updated by the previous statement.
UPDATE #FakeData SET DigitsOnly = ''
WHERE PhoneNum = '';

--	3.	Update the source table with fake phone numbers from the #temp table.
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
;WITH PermTable AS
(
	SELECT
		ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VirtualID, *
	FROM
	(
		SELECT TOP (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ') 
			source.' + QUOTENAME(@PhoneNumColumn) + '
		FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' source
	) a
),
TempTable AS
(
	SELECT
		ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VirtualID, *
	FROM
	(
		SELECT TOP (SELECT COUNT(*) FROM #FakeData) 
			f.*
		FROM #FakeData f
		ORDER BY NEWID()
	) a
)
UPDATE pt SET
	pt.' + QUOTENAME(@PhoneNumColumn) + ' = ' + 
		CASE 
			--	(xxx) yyy-zzzz
			WHEN @CharMaxLength = -1 OR @CharMaxLength >= 14 THEN 'fake.PhoneNum' 

			--	xxxyyyzzzz
			WHEN @CharMaxLength <= 11 THEN 'LEFT(fake.DigitsOnly, ' + CAST(@CharMaxLength AS NVARCHAR(MAX)) + ')' 

			--	xxx-yyy-zzzz
			WHEN @CharMaxLength = 12 THEN 'SUBSTRING(fake.PhoneNum, 2, 3) + ''-'' + RIGHT(fake.PhoneNum, 8)' 

			--	(xxx)yyy-zzzz
			WHEN @CharMaxLength = 13 THEN 'LEFT(fake.PhoneNum, 5) + RIGHT(fake.PhoneNum, 8)' 

			ELSE 'LEFT(fake.PhoneNum, ' + CAST(@CharMaxLength AS NVARCHAR(MAX)) + ')' 
		END + '
FROM PermTable pt
JOIN TempTable fake
	ON fake.VirtualID = pt.VirtualID
'
EXEC(@TSql);

SELECT @DatabaseName AS DatabaseName,
	@TableSchema AS TableSchema,
	@TableName AS TableName,
	@PhoneNumColumn AS ColumnName,
	@@ROWCOUNT AS [Number of PhoneNums obfuscated];

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
