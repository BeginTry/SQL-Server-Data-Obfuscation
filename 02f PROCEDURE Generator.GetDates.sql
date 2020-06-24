USE MLtools;
GO

CREATE OR ALTER PROCEDURE Generator.GetDates
	@DateData AS dbo.DateEntity READONLY
AS
/******************************************************************************
* Name     : Generator.GetDates
* Purpose  : Generates a table of random dates.
* Inputs   : @DateData - table type of dates.
* Outputs  : none
* Returns  : 
******************************************************************************
* Change History
*	06/24/2020	DMason	Created.
******************************************************************************/
BEGIN

--T-SQL lends itself well to creation of fake dates, so we will forgo the use
--of Machine Learning services (R, Python, or Java).
--Keep the same year for each date, but randominze the month and day.
SELECT
	DATEADD(DAY, ABS(CHECKSUM(NewId())) % 364, DATEFROMPARTS(YEAR(dd.[Value]), 1, 1)) AS FakeDates
FROM @DateData dd;


--In lieu of the above T-SQL code, the following code example will generate fake birthdates via the "generator" package for R.
/*
	DECLARE @Count BIGINT;
	SELECT @Count = COUNT_BIG(*) FROM @DateData;
	DECLARE @RScript NVARCHAR(MAX) = N'  
	library(generator)
	total_dates <- ' + CAST(@Count AS NVARCHAR(MAX)) + '

	#Birthdays.
	dfDates <- as.data.frame(as.character.Date(generator::r_date_of_births(total_dates)))
	names(dfDates) <- c("FakeDates")
	';

	EXEC sp_execute_external_script  
		@language = N'R',
		@script = @RScript,
		@output_data_1_name = N'dfDates'
	WITH RESULT SETS 
	(
		(
			FakeDates DATE
		)
	);
*/

END
GO
