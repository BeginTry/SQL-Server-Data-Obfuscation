USE MLtools;
GO

CREATE OR ALTER PROCEDURE Generator.GetSSNs
	@Count AS BIGINT,
	@FormatChar VARCHAR(1) = ''
AS
/******************************************************************************
* Name     : Generator.GetSSNs
* Purpose  : Generates a table of random social security number data.
* Inputs   : @Count - number of social security numbers to generate.
* Outputs  : none
* Returns  : (See RESULT SETS definition)
******************************************************************************
* Change History
*	03/17/2020	DMason	Created.
******************************************************************************/
BEGIN

IF @Count <= 0
BEGIN
	SELECT CAST(NULL AS VARCHAR(16))
	WHERE 1 = 2;

	RETURN;
END

DECLARE @RScript NVARCHAR(MAX) = N'  
library(generator)
total_people <- ' + CAST(@Count AS NVARCHAR(MAX)) + '

#SSNs.
SSN <- generator::r_national_identification_numbers(total_people)
SSN <- gsub("-", "' + RTRIM(@FormatChar) + '", SSN)
People <- as.data.frame(SSN)
';

EXEC sp_execute_external_script  
	@language = N'R',
	@script = @RScript,
	@output_data_1_name = N'People'
WITH RESULT SETS 
(
	(
		SSN VARCHAR(16)
	)
);
END
GO

/*
EXEC Generator.GetSSNs 10, '-';
*/
