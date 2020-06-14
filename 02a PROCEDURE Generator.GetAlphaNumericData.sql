USE MLtools;
GO

CREATE OR ALTER PROCEDURE Generator.GetAlphaNumericData
	@AlphaNumericData AS dbo.DataEntity READONLY
AS
/******************************************************************************
* Name     : Generator.GetAlphaNumericData
* Purpose  : Generates a table of random alpha-numeric data.
* Inputs   : @AlphaNumericData - table type of alpha-numeric source data.
*	The pattern for generated (fake) data is based on that of the source data.
* Outputs  : none
* Returns  : (See RESULT SETS definition)
******************************************************************************
* Change History
*	03/31/2020	DMason	Created.
******************************************************************************/
BEGIN
SELECT ad.[Value]
INTO #AlphaNumericData
FROM @AlphaNumericData ad;

EXEC sp_execute_external_script  
	@language = N'R',
	@script = N'  
library(stringi)

#Function to generate a random character, based on the input source character.
#The returned value will be either a digit or alpha character, based on
#the input source character.
fctRandomCharacter <- function(sourceChar){
	#TODO: if sourceChar is more than one character, throw an error.
	if(length(sourceChar) != 1)
		print(paste("sourceChar has length > 1:", sourceChar))
	else if(nchar(sourceChar, type = "chars") != 1)
		print(paste("sourceChar is not a single character:", sourceChar))
  
	charInt <- utf8ToInt(sourceChar)
	pat <- "[A-Za-z0-9]"
  
	if(charInt >= 48 & charInt <= 57 )
		pat <- "[0-9]"  #character is digit.
	else if(charInt >= 65 & charInt <= 90)
		pat <- "[A-Z]"  #character is upper-case letter.
	else if(charInt >= 97 & charInt <= 122)
		pat <- "[a-z]"  #character is lower-case letter.
	else
		pat <- "[!-/:-@]"	#character is neither letter nor digit.
  
	#32-47 [ -/]
	#58-64 [:-@]
	#91-96 [\[-`]
	#123-126 [{-~]
  
	stri_rand_strings(1, 1, pattern = pat)
}

#Function to generate a random string, based on the input source string.
#The returned string will be the same length as the input source string,
#Letter characters in the original source string will be replaced with 
#random letters, and digits in the original source string will be 
#replaced with random digits.
fctRandomString <- function(sourceString) {
	fChars <- strsplit(sourceString, split = "")
	fRandomChars <- lapply(fChars[[1]], function(x) fctRandomCharacter(x))
	stringi::stri_join_list(fRandomChars, sep = "", collapse = "")
}

AlphaNumericDataFaked <- apply(AlphaNumericDataSource, 1, function(x) 
	tryCatch(fctRandomString(x),
           error = function(e){
             paste("Error:", e)
           })
)
AlphaNumericDataFaked <- as.data.frame(AlphaNumericDataFaked)
',
	@input_data_1 = N'SELECT [Value] FROM #AlphaNumericData;',
	@input_data_1_name = N'AlphaNumericDataSource',
	@output_data_1_name = N'AlphaNumericDataFaked'
WITH RESULT SETS 
(
	(
		FakeAlphaNumericData NVARCHAR(255)
	)
);
END
GO

/*
DECLARE @Test AS dbo.DataEntity;
INSERT INTO @Test SELECT TOP(200) CAST(EmployeeNo AS NVARCHAR(25)) FROM Herman.dbo.Employee WHERE EmployeeNo <> '';
EXEC Generator.GetAlphaNumericData @Test;
*/