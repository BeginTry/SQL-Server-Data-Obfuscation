USE MLtools;
GO

CREATE OR ALTER PROCEDURE Generator.GetFullNames
	@Count BIGINT
AS
/******************************************************************************
* Name     : Generator.GetFullNames
* Purpose  : Generates a table of random names data (first, last, middle).
* Inputs   : @Count - number of names to generate.
* Outputs  : none
* Returns  : (See RESULT SETS definition)
******************************************************************************
* Change History
*	03/17/2020	DMason	Created.
******************************************************************************/
BEGIN

IF @Count <= 0
BEGIN
	SELECT CAST(NULL AS NVARCHAR(255)), CAST(NULL AS NVARCHAR(255)), CAST(NULL AS NVARCHAR(255))
	WHERE 1 = 2;

	RETURN;
END

DECLARE @Rscript NVARCHAR(MAX) = N' 
#install.packages("stringr")
library(generator)
total_people <- ' + CAST(@Count AS NVARCHAR(MAX)) + '

#first, last names.
nm <- generator::r_full_names(total_people)
nmSplit <- stringr::str_split(string = nm, pattern = " ", simplify = TRUE)
People <- as.data.frame(nmSplit)
names(People) <- c("FirstName", "LastName")

#middle names.
nm <- generator::r_full_names(total_people)
nmSplit <- stringr::str_split(string = nm, pattern = " ", simplify = TRUE)
People$MiddleName <- nmSplit[,1]
';

EXEC sp_execute_external_script  
	@language = N'R',
	@script = @Rscript,
	@output_data_1_name = N'People'
WITH RESULT SETS 
(
	(
		FirstName NVARCHAR(255),
		LastName NVARCHAR(255),
		MiddleName NVARCHAR(255)
	)
);
END
GO

/*
EXEC Generator.GetFullNames 10;
*/
