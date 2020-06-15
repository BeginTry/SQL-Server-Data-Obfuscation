USE MLtools;
GO

CREATE OR ALTER PROCEDURE Obfuscator.SetFullNames
	@DatabaseName SYSNAME,
	@TableSchema SYSNAME,
	@TableName SYSNAME,
	@FirstNameColumn SYSNAME,
	@LastNameColumn SYSNAME,
	@MiddleNameColumn SYSNAME = NULL,
	@DisableTriggers BIT = 1
/******************************************************************************
* Name     : Obfuscate.FullNames
* Purpose  : Randomly overwrites existing name data with fake first names, last
*		names, and middle names.
* Inputs   : @DatabaseName, @TableSchema, @TableName - 3-part name of the table.
*			 @FirstNameColumn - column name that holds the first name data.
*			 @LastNameColumn - column name that holds the last name data.
*			 @MiddleNameColumn - column name that holds the middle name data.
*			 @DisableTriggers - self-explanatory.
* Outputs  : none
* Returns  : 3-part name of the table and the number of names obfuscated.
******************************************************************************
* Change History
*	05/19/2020	DMason	Created.
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

--Verify columns exist in table, determine their max sizes and data types.
SET @TSql = 'SELECT c.COLUMN_NAME, c.CHARACTER_MAXIMUM_LENGTH, c.DATA_TYPE
FROM ' + QUOTENAME(@DatabaseName) + '.INFORMATION_SCHEMA.COLUMNS c
WHERE c.TABLE_SCHEMA = ''' + @TableSchema + '''
AND c.TABLE_NAME = ''' + @TableName + '''
AND c.COLUMN_NAME IN (''' + @FirstNameColumn + ''', ''' + @LastNameColumn + '''' + COALESCE(',''' + @MiddleNameColumn + '''', '') + ')';

DROP TABLE IF EXISTS #NameColumns;
SELECT c.COLUMN_NAME, c.CHARACTER_MAXIMUM_LENGTH, c.DATA_TYPE
INTO #NameColumns
FROM INFORMATION_SCHEMA.COLUMNS c
WHERE 1 = 2;

INSERT INTO #NameColumns
EXEC (@TSql);
--SELECT * FROM #NameColumns;

IF NOT EXISTS (SELECT * FROM #NameColumns c WHERE c.COLUMN_NAME = @FirstNameColumn)
BEGIN
	SET @Msg = 'Column ' + QUOTENAME(@FirstNameColumn) + ' does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END
ELSE IF NOT EXISTS (SELECT * FROM #NameColumns c WHERE c.COLUMN_NAME = @LastNameColumn)
BEGIN
	SET @Msg = 'Column ' + QUOTENAME(@LastNameColumn) + ' does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END
ELSE IF @MiddleNameColumn IS NOT NULL AND NOT EXISTS (SELECT * FROM #NameColumns c WHERE c.COLUMN_NAME = @MiddleNameColumn)
BEGIN
	SET @Msg = 'Column ' + QUOTENAME(@MiddleNameColumn) + ' does not exist: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 16, 1);
	RETURN;
END
ELSE 
BEGIN
	SET @Msg = '';
	SELECT @Msg = @Msg + 'Column data type not supported: ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '.' + QUOTENAME(c.COLUMN_NAME) + ' (' + c.DATA_TYPE + ')' + CHAR(13) + CHAR(10)
	FROM #NameColumns c
	WHERE c.DATA_TYPE NOT IN ('nchar', 'nvarchar', 'char', 'varchar');

	IF @@ROWCOUNT >= 1
	BEGIN
		RAISERROR(@Msg, 16, 1);
		RETURN;
	END
END


--	1.	Populate a #temp table with fake names--1 for every row in the source table.
DROP TABLE IF EXISTS #FakeNames;
CREATE TABLE #FakeNames (
	ID BIGINT IDENTITY PRIMARY KEY,
	FirstName NVARCHAR(255),
	LastName NVARCHAR(255),
	MiddleName NVARCHAR(255)
)

SET @TSql = N'SELECT @DynCount = COUNT_BIG(*) FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';';
DECLARE @RowCount BIGINT;
EXEC SP_EXECUTESQL 
	@Query  = @TSql,
	@Params = N'@DynCount BIGINT OUTPUT',
	@DynCount = @RowCount OUTPUT

IF @RowCount = 0
BEGIN
	SELECT @Msg = 'Table does not contain any rows: ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName);
	RAISERROR(@Msg, 10, 1);
	RETURN;
END

INSERT INTO #FakeNames EXEC Generator.GetFullNames @RowCount;

--	2.	Get source table counts of combinations of names value types:
--		NULL vs Zero-length string vs Single-char string vs Multi-char string.
DROP TABLE IF EXISTS #NameValueTypes;
CREATE TABLE #NameValueTypes (
	TypeCount BIGINT,
	FirstNameType TINYINT,
	LastNameType TINYINT,
	MiddleNameType TINYINT
)

SET @TSql = '
SELECT 
	COUNT(*) AS TypeCounts,
	CAST(CAST(LEN(' + QUOTENAME(@FirstNameColumn) + ') AS BIT) AS INT) AS FirstNameType,
	CAST(CAST(LEN(' + QUOTENAME(@LastNameColumn) + ') AS BIT) AS INT) AS LastNameType,
	' +
	COALESCE('CASE
		WHEN LEN(' + QUOTENAME(@MiddleNameColumn) + ') > 1 THEN 2
		ELSE LEN(' + QUOTENAME(@MiddleNameColumn) + ')
	END', 'NULL') + 
		' AS MiddleNameType
FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + '
GROUP BY CAST(CAST(LEN(' + QUOTENAME(@FirstNameColumn) + ') AS BIT) AS INT),
	CAST(CAST(LEN(' + QUOTENAME(@LastNameColumn) + ') AS BIT) AS INT)
	' +
	COALESCE(', CASE
		WHEN LEN(' + QUOTENAME(@MiddleNameColumn) + ') > 1 THEN 2
		ELSE LEN(' + QUOTENAME(@MiddleNameColumn) + ')
	END', '') + ';';
INSERT INTO #NameValueTypes EXEC(@TSql);


--	3.	Update the fake names with NULL/Zero-length strings/Single-char strings
--		as appropriate so there is a distribution that matches the source table.
ALTER TABLE #FakeNames ADD IsUpdated BIT NOT NULL DEFAULT (0);
DECLARE @TypeCount BIGINT;
DECLARE @FNameType TINYINT;
DECLARE @LNameType TINYINT;
DECLARE @MNameType TINYINT;
DECLARE curTypes CURSOR READ_ONLY FAST_FORWARD FOR
	SELECT f.TypeCount, f.FirstNameType, f.LastNameType, f.MiddleNameType
	FROM #NameValueTypes f;

OPEN curTypes;
FETCH NEXT FROM curTypes INTO @TypeCount, @FNameType, @LNameType, @MNameType;

WHILE @@FETCH_STATUS = 0
BEGIN
	UPDATE f SET
		f.IsUpdated = 1,

		--First/Last: empty string, entire name string, or NULL.
		f.FirstName = CASE WHEN @FNameType = 0 THEN '' WHEN @FNameType = 1 THEN f.FirstName ELSE NULL END,
		f.LastName = CASE WHEN @LNameType = 0 THEN '' WHEN @LNameType = 1 THEN f.LastName ELSE NULL END,

		--Middle: empty string, middle initial (first char), entire name string, or NULL.
		f.MiddleName = CASE WHEN @MNameType = 0 THEN '' WHEN @MNameType = 1 THEN LEFT(f.MiddleName, 1) WHEN @MNameType = 2 THEN f.MiddleName ELSE NULL END
	FROM #FakeNames f
	WHERE f.ID IN (
		SELECT TOP(@TypeCount) s.ID
		FROM #FakeNames s
		WHERE s.IsUpdated = 0
		ORDER BY NEWID()
	);

	FETCH NEXT FROM curTypes INTO @TypeCount, @FNameType, @LNameType, @MNameType;
END

CLOSE curTypes;
DEALLOCATE curTypes;

--	4.	Update the source table with fake names from the #temp table.

IF @DisableTriggers = 1
BEGIN
	--Disable all triggers on source table.
	SET @TSql = '
	USE ' + QUOTENAME(@DatabaseName) + ';
	DISABLE TRIGGER ALL ON ' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ';'
	EXEC(@TSql);
END

--Will need this to prevent "String or binary data would be truncated" errors.
DECLARE @MaxLen_First VARCHAR(MAX);	--VARCHARs for easier string concatenation.
DECLARE @MaxLen_Last VARCHAR(MAX);
DECLARE @MaxLen_Mid VARCHAR(MAX);

SELECT @MaxLen_First = c.CHARACTER_MAXIMUM_LENGTH FROM #NameColumns c WHERE c.COLUMN_NAME = @FirstNameColumn;
SELECT @MaxLen_Last = c.CHARACTER_MAXIMUM_LENGTH FROM #NameColumns c WHERE c.COLUMN_NAME = @LastNameColumn;
SELECT @MaxLen_Mid = c.CHARACTER_MAXIMUM_LENGTH FROM #NameColumns c WHERE c.COLUMN_NAME = @MiddleNameColumn;

--UPDATE
SET @TSql = '
;WITH SourceTable AS
(
	SELECT
		ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS VirtualID, *
	FROM
	(
		SELECT TOP (SELECT COUNT(*) FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ') 
			source.' + QUOTENAME(@LastNameColumn) + ', source.' + QUOTENAME(@FirstNameColumn) + 
				CASE WHEN @MiddleNameColumn IS NOT NULL THEN ', source.' + QUOTENAME(@MiddleNameColumn) ELSE '' END + ' 
		FROM ' + QUOTENAME(@DatabaseName) + '.' + QUOTENAME(@TableSchema) + '.' + QUOTENAME(@TableName) + ' source
		ORDER BY NEWID()
	) a
)
UPDATE st SET
	st.' + QUOTENAME(@LastNameColumn) + ' = LEFT(fake.LastName, ' + @MaxLen_First + '),
	st.' + QUOTENAME(@FirstNameColumn) + ' = LEFT(fake.FirstName, ' + @MaxLen_Last + ')' +
	CASE WHEN @MiddleNameColumn IS NOT NULL THEN ',
		st.' + QUOTENAME(@MiddleNameColumn) + ' = LEFT(fake.MiddleName, ' + @MaxLen_Mid + ')' ELSE '' END + '
FROM SourceTable st
JOIN #FakeNames fake
	ON fake.ID = st.VirtualID
'
EXEC(@TSql);

SELECT @DatabaseName AS DatabaseName,
	@TableSchema AS TableSchema,
	@TableName AS TableName,
	@@ROWCOUNT AS [Number of Names obfuscated];

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
