/*
ECG_LoadNarratives_Text

Description:
	Load the ECG narratives from a tab delimited text file ECG_Narratives.txt


Author: Richard H. Epstein, MD
Copyright (C) 2020


IMPORTANT NOTES: 
	1. The ECG_Narratives.txt file is tab delimited. A sample is provied in the project folder.
	2. The path to the folder location on the local server where the configuration files are located needs to be modified
		in the variable @DataFolderLocation
 

 The columns of this tab-delimited table ECG_Narratives.txt are
	IDX					sequential integer row from 1..n
	PATIENT_ID			patient identifier
	ORDER_ID			order number corresponding to the ECG
	ECGDate				date the ECG was taken
	ECGType				type of ECG (e.g., 12 lead)
	Line				line number of the ECG report from 1..n
	Narrative			null
	NarrativeRaw		text of each line in the narrative
	ignore				flag to ignore the line; set all = 0 initially


Syntax:
	EXEC [dbo].[ECG_LoadNarratives_Text]				-- load ECG narrative from the tab-delimited text file ECG_Narratives.txt

Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding


*/


--/*
CREATE PROC [dbo].[ECG_LoadNarratives_Text] @StartDate datetime = NULL, @EndDate datetime = NULL
AS
  --*/

  SET NOCOUNT ON

  -- **********************************************************************
  -- The @DataFolderLocation is the path to the configuration files
  -- The value of this string needs to be changed to reflect the location on the local system
  -- **********************************************************************
  -- DECLARE @DataFolderLocation varchar(1024) = '\\10.187.129.17\e$\ECG\ECG Test Files\'

  DECLARE @DataFolderLocation varchar(1024) = (SELECT TOP 1
    TestFileFolder
  FROM ECG_FolderLocations)

  DECLARE @DataFileName varchar(1024)
  DECLARE @SQL nvarchar(1024)

  SET @DataFileName = @DataFolderLocation + 'ECG_Narratives.txt'
  TRUNCATE TABLE dbo.ECG_Narratives


  SET @SQL =
  N'BULK INSERT dbo.ECG_Narratives FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	DATAFILETYPE = ''widechar'',
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)



