USE MLtools;
GO

CREATE OR ALTER PROCEDURE Obfuscator.SetDates
	@DatabaseName SYSNAME,
	@TableSchema SYSNAME,
	@TableName SYSNAME,
	@DateColumn SYSNAME,
	@DisableTriggers BIT = 1
/******************************************************************************
* Name     : Obfuscate.Dates
* Purpose  : Randomly overwrites existing DATE data with fake DATE data.
* Inputs   : 3-part name of the table, plus column name that holds the DATE.
* Outputs  : Nothing
* Returns  : Nothing
******************************************************************************
* Change History
*	06/24/2020	DMason	Created.
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

--Verify column exists in table, determine its data type.
DECLARE @DataType SYSNAME;
SET @TSql = 'SELECT @Type = DATA_TYPE
FROM ' + QUOTENAME(@DatabaseName) + '.INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = ''' + @TableSchema + '''
AND c.TABLE_NAME = ''' + @TableName + '''
AND c.COLUMN_NAME = ''' + @DateColumn + '''
';

EXECUTE sp_executesql 
    @TSql, 
    N'@Type SYSNAME OUTPUT', 
    @DataType OUTPUT;
--SELECT @DataType;

IF @DataType IS NULL
BEGIN
	SET @Msg = 'Column does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@DateColumn);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END
ELSE IF @DataType NOT IN ('date', 'datetime', 'datetime2', 'smalldatetime')
BEGIN
	SET @Msg = 'Column data type does not support DATE data: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(@DateColumn) + ' (' + @DataType + ')';
	RAISERROR(@Msg, 16, 1);
	RETURN;
END


--	1.	Get source table counts of date value types:
--		NULL vs "Zero" date vs other date.
DECLARE @NullCount BIGINT;
DECLARE @ZeroDateCount BIGINT;
DECLARE @ValueCount BIGINT;
DECLARE @TotalCount BIGINT;

SET @TSql = N'SELECT
	@Count1 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@DateColumn) + ' IS NULL THEN 1 ELSE 0 END AS BIGINT)),
	@Count2 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@DateColumn) + ' = CAST(0 AS DATETIME) THEN 1 ELSE 0 END AS BIGINT)),
	@Count3 = SUM(CAST(CASE WHEN t.' + QUOTENAME(@DateColumn) + ' <> CAST(0 AS DATETIME) THEN 1 ELSE 0 END AS BIGINT)),
	@Count4 = COUNT_BIG(*)
FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' t;';
EXEC sp_executesql 
	@Query  = @TSql,
	@Params = N'@Count1 BIGINT OUTPUT, @Count2 BIGINT OUTPUT, @Count3 BIGINT OUTPUT, @Count4 BIGINT OUTPUT',
	@Count1 = @NullCount OUTPUT,
	@Count2 = @ZeroDateCount OUTPUT,
	@Count3 = @ValueCount OUTPUT,
	@Count4 = @TotalCount OUTPUT

IF @TotalCount = 0
BEGIN
	SELECT @Msg = 'Table does not contain any rows: ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 10, 1);
	RETURN;
END


--	2.	Populate a #temp table with fake date values--1 for every row in the source table.
DECLARE @DateData AS dbo.DateEntity;
SET @TSql = 'SELECT ' + QUOTENAME(@DateColumn) + ' 
	FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '
	WHERE ' + QUOTENAME(@DateColumn) + ' <> CAST(0 AS DATETIME);';
INSERT INTO @DateData EXEC(@TSql);

DROP TABLE IF EXISTS #FakeData;
CREATE TABLE #FakeData (
	DateData DATE
)

--Equivalent number of fake date values.
INSERT INTO #FakeData EXEC Generator.GetDates @DateData;
DELETE FROM @DateData;	--No longer needed.

--Equivalent number of NULL dates.
INSERT INTO #FakeData (DateData)
SELECT TOP(@NullCount) NULL
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3

--Equivalent number of "zero value" dates.
INSERT INTO #FakeData (DateData)
SELECT TOP(@ZeroDateCount) ''
FROM master.dbo.spt_values v1
CROSS JOIN master.dbo.spt_values v2
CROSS JOIN master.dbo.spt_values v3


--	3.	Update the source table with fake Dates from the #temp table.
IF @DisableTriggers = 1
BEGIN
	--Disable all triggers on source table.
	SET @TSql = '
	USE ' + QUOTENAME(@DatabaseName) + ';
	DISABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';'
	EXEC(@TSql);
END

--UPDATE
SET @TSql = '
;WITH PermTable AS
(
	SELECT
		ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VirtualID, *
	FROM
	(
		SELECT TOP (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ') 
			source.' + QUOTENAME(@DateColumn) + '
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
	pt.' + QUOTENAME(@DateColumn) + ' = fake.DateData
FROM PermTable pt
JOIN TempTable fake
	ON fake.VirtualID = pt.VirtualID
'
EXEC(@TSql);

SELECT @DatabaseName AS DatabaseName,
	@TableSchema AS TableSchema,
	@TableName AS TableName,
	@DateColumn AS ColumnName,
	@@ROWCOUNT AS [Number of dates obfuscated];

IF @DisableTriggers = 1
BEGIN
	--Enable all triggers on source table.
	SET @TSql = '
	USE ' + QUOTENAME(@DatabaseName) + ';
	ENABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';'
	EXEC(@TSql);
END

UPDATE dbo.DataDiscoveryAndClassification
SET IsObfuscated = 1
WHERE DatabaseName = @DatabaseName
AND SchemaName = @TableSchema
AND TableName = @TableName
AND ColumnName = @DateColumn

END
GO
