USE MLtools;
GO

CREATE OR ALTER PROCEDURE Generator.GetPhoneNumbers
	@Count BIGINT
AS
/******************************************************************************
* Name     : Generator.GetPhoneNumbers
* Purpose  : Generates a table of random phone number data.
* Inputs   : @Count - number of phone numbers to generate.
* Outputs  : none
* Returns  : (See RESULT SETS definition)
******************************************************************************
* Change History
*	03/17/2020	DMason	Created.
******************************************************************************/
BEGIN

DECLARE @RScript NVARCHAR(MAX) = N'  
library(generator)
total_people <- ' + CAST(@Count AS NVARCHAR(MAX)) + '

#Phone numbers. Use the logical/boolean arguments to include hyphens, parentheses, and spaces.
#The resulting formatting is a little strange, so use gsub() to replace unwanted characters.
People <- as.data.frame(
  gsub("- ", "-", gsub(")-", ")", generator::r_phone_numbers(total_people, TRUE, TRUE, TRUE)))
)
names(People) <- c("PhoneNumber")
';

EXEC sp_execute_external_script  
	@language = N'R',
	@script = @RScript,
	@output_data_1_name = N'People'
WITH RESULT SETS 
(
	(
		PhoneNumber NVARCHAR(32)
	)
);
END
GO

/*
EXEC Generator.GetPhoneNumbers 15;
*/