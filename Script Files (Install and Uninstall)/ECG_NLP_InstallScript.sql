
/*
Installation script for the ECG NLP processing system

ECG_NLP_InstallScript.sql

Copyright (C) 2021 Richard H. Epstein, MD
System may be used or modified for non-commerical applications with acknowledgment of the source of the code
Commercial use is prohibited without licensure from the author


NOTE: The location of the @ConfigurationFolder and @TestFileFolder paths must be changed before executing this script

Acknowledgments: SQL CODE was beautified from the original stored procedures using  https://sql-format.com/


Version Control
Date		version		by		Notes
06/30/21	1.01		RHE		Original coding


*/


SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- ************************************************************************************************************
-- * BEFORE EXECUTING THIS SQL SCRIPT, THE 2 PATHS BELOW MUST BE CHANGED TO THE FOLDER LOCATION ON THE SERVER *
-- ************************************************************************************************************
-- replace the value with the path for the Configuration Files folder; should end with a \
DECLARE @ConfigurationFolder varchar(255) = '\\10.187.129.17\e$\ECG\Configuration Files\'

-- replace the value with the path for the ECG Test Files folder; should end with a \
DECLARE @TestFileFolder varchar(255) = '\\10.187.129.17\e$\ECG\ECG Test Files\'

-- make sure the paths end with a \ and than any spaces at the end of the string are removed
SET @ConfigurationFolder = RTRIM(@ConfigurationFolder)
SET @TestFileFolder = RTRIM(@TestFileFolder)

IF RIGHT(@ConfigurationFolder, 1) <> '\'
  SET @ConfigurationFolder = @ConfigurationFolder + '\'
IF RIGHT(@TestFileFolder, 1) <> '\'
  SET @TestFileFolder = @TestFileFolder + '\'


-- drop the existing ECG NLP folder location table if present
IF OBJECT_ID('dbo.ECG_FolderLocations') IS NOT NULL
  DROP TABLE dbo.ECG_FolderLocations

CREATE TABLE dbo.ECG_FolderLocations (
  ConfigurationFolder varchar(255),
  TestFileFolder varchar(255)
)

TRUNCATE TABLE dbo.ECG_FolderLocations
INSERT INTO dbo.ECG_FolderLocations
  SELECT
    @ConfigurationFolder,
    @TestFileFolder


SELECT
  *
FROM dbo.ECG_FolderLocations

select 'NOTE: The install will fail if you do not have BULK INSERT privileges or the path to the Configuration Folder or Test File Folder is incorrect' as Message

-- drop existing ECG NLP stored procedures
IF OBJECT_ID('dbo.ECG_CreateTablesForNLProcessing') IS NOT NULL
  DROP PROC dbo.ECG_CreateTablesForNLProcessing
IF OBJECT_ID('dbo.ECG_DetermineEpicECGIdentifiers') IS NOT NULL
  DROP PROC dbo.ECG_DetermineEpicECGIdentifiers
IF OBJECT_ID('dbo.ECG_IdentifyMisspelledWords') IS NOT NULL
  DROP PROC dbo.ECG_IdentifyMisspelledWords
IF OBJECT_ID('dbo.ECG_LoadNarratives_Epic') IS NOT NULL
  DROP PROC dbo.ECG_LoadNarratives_Epic
IF OBJECT_ID('dbo.ECG_LoadNarratives_Text') IS NOT NULL
  DROP PROC dbo.ECG_LoadNarratives_Text
IF OBJECT_ID('dbo.ECG_PreProcessNarratives') IS NOT NULL
  DROP PROC dbo.ECG_PreProcessNarratives
IF OBJECT_ID('dbo.ECG_ProcessNarratives') IS NOT NULL
  DROP PROC dbo.ECG_ProcessNarratives
IF OBJECT_ID('dbo.Epic_Find_PROC_ID_ECGinLabs') IS NOT NULL
  DROP PROC dbo.Epic_Find_PROC_ID_ECGinLabs


GO
/*
ECG_CreateTablesForNLProcessing

Description:
	Creates the database for the ECG NLP system and populate the tables

Author: Richard H. Epstein, MD
Copyright (C) 2020

IMPORTANT NOTES: 
	Modify the stored procedure to set the variable @DataFolderLocation = path to the server folder containing the configuration files
	This stored procedure should be executed in the database in which the tables will reside
	The user must have the BULKADMIN server role enabled to use the BULK INSERT command
	The tab-delimited text files containing the configuration information must be closed when executing



Syntax
EXEC dbo.ECG_CreateTablesForNLProcessing			-- Creates tables if absent, then truncate and reload the tables from the configuration files
EXEC dbo.ECG_CreateTablesForNLProcessing	1		-- Drop all tables, then recreate and load the configuration tables from the configuration files.

View Table Contents
	SELECT top 100 * FROM dbo.ECG_Narratives
	SELECT top 100 * FROM dbo.ECG_ResultsQuantitative 
	SELECT top 100 * FROM dbo.ECG_ResultsDiagnostic 
	SELECT top 100 * FROM dbo.ECG_Performance
	SELECT top 100 * FROM dbo.ECG_Spelling 

	SELECT * FROM dbo.ECG_DiagnosisMatch 
	SELECT * FROM dbo.ECG_DiagnosisExclusions 
	SELECT * FROM dbo.ECG_HedgePhrases 
	SELECT * FROM dbo.ECG_MatchTypeExclusion 
	SELECT * FROM dbo.ECG_Misspellings Misspellings
	SELECT * FROM dbo.ECG_SpellingSentencesExcluded 
	SELECT * FROM dbo.ECG_DiagnosesNoLongerPresent 
	SELECT * FROM dbo.ECG_QuantitativeMatch 
	



Date		Ver		By		Comment
09/11/20	1.00	RHE		Initial Coding
01/13/21	2.00	RHE		Modified for distribution externally on Google Drive
02/18/21	2.01	RHE		Add the Raw Narrative to the table dbo.ECG_ResultsDiagnostic

*/


--/*
CREATE PROC [dbo].[ECG_CreateTablesForNLProcessing] @RebuildSchema tinyint = 0
AS
  --*/

  SET NOCOUNT ON

  /* -- uncomment for manual execuation
 DECLARE @RebuildSchema tinyint = 1	-- 1 = delete all tables and rebuild, 0 = only create tables if they are missing
 --*/

  -- **********************************************************************
  -- The @DataFolderLocation is the path to the configuration files
  -- The value of this string needs to be changed to reflect the location on the local system
  -- **********************************************************************
  -- DECLARE @DataFolderLocation varchar(1024) = '\\10.187.129.17\e$\ECG\Configuration Files\'  --'D:\UserData\Projects\ECG_NLP\'

  DECLARE @DataFolderLocation varchar(1024) = (SELECT TOP 1
    ConfigurationFolder
  FROM ECG_FolderLocations)

  -- ***************************************
  -- delete the temporary tables, if present
  -- ***************************************
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosisExclusions') IS NOT NULL
    DROP TABLE #ECG_DiagnosisExclusions
  IF OBJECT_ID('tempdb.dbo.#ECG_HedgePhrases') IS NOT NULL
    DROP TABLE #ECG_HedgePhrases
  IF OBJECT_ID('tempdb.dbo.#ECG_MatchTypeExclusions') IS NOT NULL
    DROP TABLE #ECG_MatchTypeExclusions
  IF OBJECT_ID('tempdb.dbo.#ECG_Spelling') IS NOT NULL
    DROP TABLE #ECG_Spelling
  IF OBJECT_ID('tempdb.dbo.#ECG_QuantitativeMatch') IS NOT NULL
    DROP TABLE #ECG_QuantitativeMatch
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosisMatch') IS NOT NULL
    DROP TABLE #ECG_DiagnosisMatch
  IF OBJECT_ID('tempdb.dbo.#ECG_Misspellings') IS NOT NULL
    DROP TABLE #ECG_Misspellings

  -- ********************************************************************
  --	Delete schema and rebuild if @RebuildSchema = 1, otherwise, skip
  -- ********************************************************************
  IF @RebuildSchema = 1
  BEGIN
    IF OBJECT_ID('ECG_ResultsQuantitative') IS NOT NULL
      DROP TABLE dbo.ECG_ResultsQuantitative
    IF OBJECT_ID('ECG_ResultsDiagnostic') IS NOT NULL
      DROP TABLE dbo.ECG_ResultsDiagnostic
    IF OBJECT_ID('ECG_Narratives') IS NOT NULL
      DROP TABLE dbo.ECG_Narratives
    IF OBJECT_ID('ECG_DiagnosisMatch') IS NOT NULL
      DROP TABLE dbo.ECG_DiagnosisMatch
    IF OBJECT_ID('ECG_DiagnosisExclusions') IS NOT NULL
      DROP TABLE dbo.ECG_DiagnosisExclusions
    IF OBJECT_ID('ECG_HedgePhrases') IS NOT NULL
      DROP TABLE dbo.ECG_HedgePhrases
    IF OBJECT_ID('ECG_MatchTypeExclusion') IS NOT NULL
      DROP TABLE dbo.ECG_MatchTypeExclusion
    IF OBJECT_ID('ECG_Spelling') IS NOT NULL
      DROP TABLE dbo.ECG_Spelling
    IF OBJECT_ID('ECG_Misspellings') IS NOT NULL
      DROP TABLE dbo.ECG_Misspellings
    IF OBJECT_ID('ECG_SpellingSentencesExcluded') IS NOT NULL
      DROP TABLE dbo.ECG_SpellingSentencesExcluded
    IF OBJECT_ID('ECG_DiagnosesNoLongerPresent') IS NOT NULL
      DROP TABLE dbo.ECG_DiagnosesNoLongerPresent
    IF OBJECT_ID('ECG_QuantitativeMatch') IS NOT NULL
      DROP TABLE dbo.ECG_QuantitativeMatch
    IF OBJECT_ID('ECG_PerformanceAllNarratives') IS NOT NULL
      DROP TABLE dbo.ECG_PerformanceAllNarratives
    IF OBJECT_ID('ECG_PerformanceDiscreteNarratives') IS NOT NULL
      DROP TABLE ECG_PerformanceDiscreteNarratives
  END


  -- ********************************************************************
  -- Create tables used for processing the ECG narratives if they do not already exist in the current database
  -- ********************************************************************

  -- This is the table for the quantitative data from the processed ECG narrative reports
  IF OBJECT_ID('ECG_ResultsQuantitative') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_ResultsQuantitative (
      IDX int IDENTITY (1, 1),
      pat_id varchar(18),
      ORDER_PROC_ID numeric(18),
      EKGDate datetime,
      Description varchar(30),
      Indication varchar(100),
      QT smallint,
      P_Axis smallint,
      R_Axis smallint,
      T_Axis smallint,
      QRS smallint,
      PR smallint,
      QTc smallint,
      V_Rate smallint,
      A_Rate smallint,
      Interpreter varchar(255),
      InterpretationTime datetime
    )
  END


  -- This is the table for the diagnostic information from the processed ECG narrative reports
  IF OBJECT_ID('dbo.ECG_ResultsDiagnostic') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_ResultsDiagnostic (
      IDX int IDENTITY (1, 1),
      pat_id varchar(18),
      ORDER_PROC_ID numeric(18),
      EKGDate datetime,
      NarrativeRaw varchar(1024),
      Narrative varchar(1024),
      Code varchar(3),
      Diagnosis varchar(255),
      DiagnosisUncertain tinyint
    )
  END


  -- Table into which the ECG narrative should be loaded for processing
  IF OBJECT_ID('dbo.ECG_Narratives') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_Narratives (
      IDX int IDENTITY (1, 1),	--	sequential row identifier
      PATIENT_ID varchar(16),		--	patient identifier
      ORDER_PROC_ID varchar(16),		--	ecg order number
      ECGDate datetime,			--	date of the ecg
      ECGDescription varchar(100),		--	type of ecg
      LineNumber int,				--	line number of the narrative
      Narrative varchar(1024),		--	text on the line after spelling corrections, other edits
      NarrativeRaw varchar(1024),		--	text on the line before any processing (raw)
      ignore tinyint
    )
  END


  IF OBJECT_ID('dbo.ECG_DiagnosisMatch') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_DiagnosisMatch (
      IDX int IDENTITY,
      Category varchar(100),
      Code int,
      Diagnosis varchar(100),
      Match1 varchar(100),
      Match2 varchar(100),
      Match3 varchar(100),
      Match4 varchar(100),
      Match5 varchar(100),
      Match6 varchar(100),
      Match7 varchar(100),
      Match8 varchar(100),
      Match9 varchar(100),
      Match10 varchar(100),
      Exclude1 varchar(100),
      Exclude2 varchar(100),
      Exclude3 varchar(100),
      Exclude4 varchar(100),
      Exclude5 varchar(100),
      SQL varchar(8000)
    )
  END


  IF OBJECT_ID('dbo.ECG_DiagnosisExclusions') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_DiagnosisExclusions (
      IDX int IDENTITY,
      Phrase varchar(100)
    )
  END


  IF OBJECT_ID('dbo.ECG_HedgePhrases') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_HedgePhrases (
      IDX int IDENTITY,
      Code char(3),
      Phrase varchar(100)
    )
  END


  IF OBJECT_ID('dbo.ECG_MatchTypeExclusion') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_MatchTypeExclusion (
      IDX int IDENTITY,
      MatchType smallint,
      ExcludeMatchString varchar(100)
    )
  END


  IF OBJECT_ID('dbo.ECG_Spelling') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_Spelling (
      IDX int IDENTITY,
      Word varchar(100)
    )
  END


  IF OBJECT_ID('dbo.ECG_Misspellings') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_Misspellings (
      IDX int IDENTITY,
      Bad varchar(100),
      Good varchar(100)
    )
  END



  IF OBJECT_ID('dbo.ECG_SpellingSentencesExcluded') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_SpellingSentencesExcluded (
      IDX int IDENTITY,
      Phrase varchar(100)
    )
  END


  IF OBJECT_ID('dbo.ECG_DiagnosesNoLongerPresent') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_DiagnosesNoLongerPresent (
      IDX int IDENTITY,
      ReplacementType varchar(6),
      Phrase varchar(100),
      [Before Correction] varchar(255),
      [Afer Correction] varchar(255)
    )
  END


  IF OBJECT_ID('dbo.ECG_QuantitativeMatch') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_QuantitativeMatch (
      IDX int IDENTITY (1, 1),
      MatchType smallint,
      MatchString varchar(100), --	string to search for
      VariableName varchar(60), --	name of the value to report
      Offset smallint,		  --	offset # of chars from the start of the match string to the first character/digit of the value
      StringLength smallint,	  --    number of characters in the value; 999 means rest of the line
      Allow0 tinyint,			  --	if 0 means that a value of 0 is not allowed and will be replaced with a null if empty; 1 means the value can be 0
      StringValue tinyint		  --    1 means that the value is a string; 0 an integer
    )
  END


  IF OBJECT_ID('dbo.ECG_PerformanceAllNarratives') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_PerformanceAllNarratives (
      NarrativeID int,				-- sequential ID of the distinct narratives processed
      Narrative varchar(1024),		-- text of the ECG narrative line
      Code varchar(4),				-- diagnosis code from the ECG ontology
      Diagnosis varchar(255),			-- diagnosis from the NLP 
      HedgePhrase varchar(100),		-- phrase used to indicate uncertainty of the diagnosis, if applicable
      n int							-- # of occurrence of the narrative in the ECG_Narratives table processed
    )
  END

  IF OBJECT_ID('dbo.ECG_PerformanceDiscreteNarratives') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_PerformanceDiscreteNarrativeS (
      Narrative varchar(1024),		-- text of the ECG narrative line
      Code varchar(4),				-- diagnosis code from the ECG ontology
      Diagnosis varchar(255),			-- diagnosis from the NLP 
      HedgePhrase varchar(100),		-- phrase used to indicate uncertainty of the diagnosis, if applicable
      n int							-- # of occurrence of the narrative in the ECG_Narratives table processed
    )
  END

  IF OBJECT_ID('dbo.ECG_PerformanceNarrativesWithoutDiagnosis') IS NULL
  BEGIN
    CREATE TABLE dbo.ECG_PerformanceNarrativesWithoutDiagnosis (
      Narrative varchar(1024),		-- text of the ECG narrative line that is not matched to a diagnosis
      n int							-- # of occurrence of the narrative in the ECG_Narratives table processed
    )
  END



  -- ********************************************************************
  -- Create temp tables for importing the tab-delimted text files
  -- ********************************************************************

  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosisMatch') IS NULL
  BEGIN
    CREATE TABLE #ECG_DiagnosisMatch (
      Category varchar(100),
      Code int,
      Diagnosis varchar(100),
      Match1 varchar(100),
      Match2 varchar(100),
      Match3 varchar(100),
      Match4 varchar(100),
      Match5 varchar(100),
      Match6 varchar(100),
      Match7 varchar(100),
      Match8 varchar(100),
      Match9 varchar(100),
      Match10 varchar(100),
      Exclude1 varchar(100),
      Exclude2 varchar(100),
      Exclude3 varchar(100),
      Exclude4 varchar(100),
      Exclude5 varchar(100),
      SQL varchar(8000)
    )
  END

  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosisExclusions') IS NULL
  BEGIN
    CREATE TABLE #ECG_DiagnosisExclusions (
      Phrase varchar(100)
    )
  END

  IF OBJECT_ID('tempdb.dbo.#ECG_HedgePhrases') IS NULL
  BEGIN
    CREATE TABLE #ECG_HedgePhrases (
      Code char(3),
      Phrase varchar(100)
    )
  END


  IF OBJECT_ID('tempdb.dbo.#ECG_MatchTypeExclusion') IS NULL
  BEGIN
    CREATE TABLE #ECG_MatchTypeExclusion (
      MatchType smallint,
      ExcludeMatchString varchar(100)
    )
  END

  IF OBJECT_ID('tempdb.dbo.#ECG_Misspellings') IS NULL
  BEGIN
    CREATE TABLE #ECG_Misspellings (
      Bad varchar(100),
      Good varchar(100)
    )
  END

  IF OBJECT_ID('tempdb.dbo.#ECG_Spelling') IS NULL
  BEGIN
    CREATE TABLE #ECG_Spelling (
      Word varchar(100),
    )
  END

  IF OBJECT_ID('tempdb.dbo.#ECG_SpellingSentencesExcluded') IS NULL
  BEGIN
    CREATE TABLE #ECG_SpellingSentencesExcluded (
      Phrase varchar(100),
    )
  END


  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosesNoLongerPresent') IS NULL
  BEGIN
    CREATE TABLE #ECG_DiagnosesNoLongerPresent (
      ReplacementType varchar(6),
      Phrase varchar(100),
      [Before Correction] varchar(255),
      [After Correction] varchar(255)
    )
  END


  IF OBJECT_ID('tempdb.dbo.#ECG_QuantitativeMatch') IS NULL
  BEGIN
    CREATE TABLE #ECG_QuantitativeMatch (
      MatchType smallint,
      MatchString varchar(100), --	string to search for
      VariableName varchar(60), --	name of the value to report
      Offset smallint,		  --	offset # of chars from the start of the match string to the first character/digit of the value
      StringLength smallint,	  --    number of characters in the value; 999 means rest of the line
      Allow0 tinyint,			  --	if 0 means that a value of 0 is not allowed and will be replaced with a null if empty; 1 means the value can be 0
      StringValue tinyint		  --    1 means that the value is a string; 0 an integer
    )
  END


  -- **********************************************************
  -- Import data into the lookup tables from the user specified location
  -- These tables are tab delimited
  -- **********************************************************

  DECLARE @SQL nvarchar(1024)
  DECLARE @DataFileName varchar(1024)


  SET @DataFileName = @DataFolderLocation + 'ECG_DiagnosisMatch.txt'
  TRUNCATE TABLE #ECG_DiagnosisMatch
  SET @SQL =
  N'BULK INSERT #ECG_DiagnosisMatch FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)

  -- add an IDX index to this table after the import
  ALTER TABLE #ECG_DiagnosisMatch ADD IDX integer IDENTITY (1, 1)


  SET @DataFileName = @DataFolderLocation + 'ECG_SpellingSentencesExcluded.txt'
  TRUNCATE TABLE #ECG_SpellingSentencesExcluded
  SET @SQL =
  N'BULK INSERT #ECG_SpellingSentencesExcluded FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW=2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_DiagnosisExclusions.txt'
  TRUNCATE TABLE #ECG_DiagnosisExclusions
  SET @SQL =
  N'BULK INSERT #ECG_DiagnosisExclusions FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)

  SET @DataFileName = @DataFolderLocation + 'ECG_HedgePhrases.txt'
  TRUNCATE TABLE #ECG_HedgePhrases
  SET @SQL =
  N'BULK INSERT #ECG_HedgePhrases FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_MatchTypeExclusions.txt'
  TRUNCATE TABLE #ECG_MatchTypeExclusion
  SET @SQL =
  N'BULK INSERT #ECG_MatchTypeExclusion FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_DiagnosisExclusions.txt'
  TRUNCATE TABLE #ECG_DiagnosisExclusions
  SET @SQL =
  N'BULK INSERT #ECG_DiagnosisExclusions FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_Misspellings.txt'
  TRUNCATE TABLE #ECG_Misspellings
  SET @SQL =
  N'BULK INSERT #ECG_Misspellings FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_Spelling.txt'
  TRUNCATE TABLE #ECG_Spelling
  SET @SQL =
  N'BULK INSERT #ECG_Spelling FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_DiagnosesNoLongerPresent.txt'
  TRUNCATE TABLE #ECG_DiagnosesNoLongerPresent
  SET @SQL =
  N'BULK INSERT #ECG_DiagnosesNoLongerPresent FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)


  SET @DataFileName = @DataFolderLocation + 'ECG_QuantitativeMatch.txt'
  TRUNCATE TABLE #ECG_QuantitativeMatch
  SET @SQL =
  N'BULK INSERT #ECG_QuantitativeMatch FROM ''' + RTRIM(@DataFileName) +
  ''' 
WITH
(
	FIRSTROW = 2,
	FIELDTERMINATOR = ''\t'',
	ROWTERMINATOr = ''\n''
)'
  EXEC (@SQL)



  -- *******************************************
  -- Build the SQL statements for the diagnosis matches
  -- *******************************************
  -- this is what was used for evaluation of distinct narrative lines. 
  -- each SQL is applied to every ECG narrative

  UPDATE #ECG_DiagnosisMatch
  SET SQL = x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match1 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match1 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match1, '') <> '') x
    ON a.idx = x.idx

  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match2 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match2 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match2, '') <> '') x
    ON a.idx = x.idx




  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match3 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match3 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match3, '') <> '') x
    ON a.idx = x.idx


  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match4 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match4 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match4, '') <> '') x
    ON a.idx = x.idx


  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match5 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match5 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match5, '') <> '') x
    ON a.idx = x.idx


  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match6 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match6 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match6, '') <> '') x
    ON a.idx = x.idx



  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match7 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match7 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match7, '') <> '') x
    ON a.idx = x.idx



  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match8 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match8 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match8, '') <> '') x
    ON a.idx = x.idx



  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match9 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match9 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match9, '') <> '') x
    ON a.idx = x.idx


  UPDATE #ECG_DiagnosisMatch
  SET SQL = ISNULL(a.SQL, '') + x.SQL
  FROM #ECG_DiagnosisMatch a
  INNER JOIN (SELECT
    IDX,
    'insert into #DiagnosisEvaluation select  PAT_ID, ORDER_PROC_ID, CONTACT_DATE as ECGDate, NarrativeRaw, Narrative, '''
    + RIGHT('00' + RTRIM(CONVERT(char, Code)), 3) + ''' as Code, '''
    + RTRIM(Diagnosis) + ''' as Diagnosis, 0 as DiagnosisUncertain, '
    + 'patindex(''%' + Match10 + '%'',Narrative) as MatchLocation, Ignore '
    + 'from #EKG '
    + 'WHERE Narrative like ''%' + Match10 + '%'' '
    +
    CASE
      WHEN ISNULL(Exclude1, '') <> '' THEN ' AND Narrative not like ''%' + Exclude1 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude2, '') <> '' THEN ' AND Narrative not like ''%' + Exclude2 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude3, '') <> '' THEN ' AND Narrative not like ''%' + Exclude3 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude4, '') <> '' THEN ' AND Narrative not like ''%' + Exclude4 + '%'' '
      ELSE ''
    END
    +
    CASE
      WHEN ISNULL(Exclude5, '') <> '' THEN ' AND Narrative not like ''%' + Exclude5 + '%'' '
      ELSE ''
    END
    + '; '
    AS SQL
  FROM #ECG_DiagnosisMatch
  WHERE ISNULL(Match10, '') <> '') x
    ON a.idx = x.idx



  -- ****************************************
  -- update the lookup tables with new values
  -- ****************************************
  TRUNCATE TABLE dbo.ECG_DiagnosisExclusions
  INSERT INTO dbo.ECG_DiagnosisExclusions
    SELECT
      a.*
    FROM #ECG_DiagnosisExclusions a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_DiagnosisExclusions a
    INNER JOIN dbo.ECG_DiagnosisExclusions b
      ON a.Phrase = b.Phrase) x
      ON a.Phrase = x.Phrase
    WHERE x.Phrase IS NULL

  TRUNCATE TABLE dbo.ECG_HedgePhrases
  INSERT INTO dbo.ECG_HedgePhrases
    SELECT
      a.*
    FROM #ECG_HedgePhrases a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_HedgePhrases a
    INNER JOIN dbo.ECG_HedgePhrases b
      ON a.Code = b.Code
      AND a.Phrase = b.Phrase) x
      ON a.Code = x.Code
      AND a.Phrase = x.Phrase
    WHERE x.Code IS NULL
    AND x.Phrase IS NULL

  TRUNCATE TABLE dbo.ECG_MatchTypeExclusion
  INSERT INTO dbo.ECG_MatchTypeExclusion
    SELECT
      a.*
    FROM #ECG_MatchTypeExclusion a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_MatchTypeExclusion a
    INNER JOIN dbo.ECG_MatchTypeExclusion b
      ON a.MatchType = b.MatchType
      AND a.ExcludeMatchString = b.ExcludeMatchString) x
      ON a.MatchType = x.MatchType
      AND a.ExcludeMatchString = x.ExcludeMatchString
    WHERE x.MatchType IS NULL
    AND x.ExcludeMatchString IS NULL

  TRUNCATE TABLE dbo.ECG_Misspellings
  INSERT INTO dbo.ECG_Misspellings
    SELECT
      a.*
    FROM #ECG_Misspellings a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_Misspellings a
    INNER JOIN dbo.ECG_Misspellings b
      ON a.Bad = b.Bad
      AND a.Good = b.Good) x
      ON a.Bad = x.Bad
      AND a.Good = x.Good
    WHERE x.Bad IS NULL
    AND x.Good IS NULL

  TRUNCATE TABLE dbo.ECG_Spelling
  INSERT INTO dbo.ECG_Spelling
    SELECT
      a.*
    FROM #ECG_Spelling a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_Spelling a
    INNER JOIN dbo.ECG_Spelling b
      ON a.word = b.word) x
      ON a.Word = x.Word
    WHERE x.word IS NULL


  TRUNCATE TABLE dbo.ECG_SpellingSentencesExcluded
  INSERT INTO dbo.ECG_SpellingSentencesExcluded
    SELECT
      a.*
    FROM #ECG_SpellingSentencesExcluded a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_SpellingSentencesExcluded a
    INNER JOIN dbo.ECG_SpellingSentencesExcluded b
      ON a.Phrase = b.Phrase) x
      ON a.Phrase = x.Phrase
    WHERE x.Phrase IS NULL

  TRUNCATE TABLE dbo.ECG_DiagnosesNoLongerPresent
  INSERT INTO dbo.ECG_DiagnosesNoLongerPresent
    SELECT
      a.*
    FROM #ECG_DiagnosesNoLongerPresent a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_DiagnosesNoLongerPresent a
    INNER JOIN dbo.ECG_DiagnosesNoLongerPresent b
      ON a.Phrase = b.Phrase
      AND a.ReplacementType = b.ReplacementType) x
      ON a.Phrase = x.Phrase
      AND a.ReplacementType = x.ReplacementType
    WHERE x.Phrase IS NULL

  TRUNCATE TABLE dbo.ECG_DiagnosisMatch
  INSERT INTO dbo.ECG_DiagnosisMatch
    SELECT
      a.Category,
      a.Code,
      a.Diagnosis,
      a.Match1,
      a.Match2,
      a.Match3,
      a.Match4,
      a.Match5,
      a.Match6,
      a.Match7,
      a.Match8,
      a.Match9,
      a.Match10,
      a.Exclude1,
      a.Exclude2,
      a.Exclude3,
      a.Exclude4,
      a.Exclude5,
      a.SQL
    FROM #ECG_DiagnosisMatch a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_DiagnosisMatch a
    INNER JOIN dbo.ECG_DiagnosisMatch b
      ON a.SQL = b.SQL) x
      ON a.SQL = x.SQL
    WHERE x.SQL IS NULL


  TRUNCATE TABLE dbo.ECG_QuantitativeMatch
  INSERT INTO dbo.ECG_QuantitativeMatch
    SELECT
      a.MatchType,
      a.MatchString,
      a.VariableName,
      a.Offset,
      a.StringLength,
      a.Allow0,
      a.StringValue
    FROM #ECG_QuantitativeMatch a
    LEFT JOIN (SELECT
      a.*
    FROM #ECG_QuantitativeMatch a
    INNER JOIN dbo.ECG_QuantitativeMatch b
      ON a.MatchString = b.MatchString) x
      ON a.MatchString = x.MatchString
    WHERE x.MatchString IS NULL


  -- ***************************************
  -- delete the temporary tables, if present
  -- ***************************************
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosisExclusions') IS NOT NULL
    DROP TABLE #ECG_DiagnosisExclusions
  IF OBJECT_ID('tempdb.dbo.#ECG_HedgePhrases') IS NOT NULL
    DROP TABLE #ECG_HedgePhrases
  IF OBJECT_ID('tempdb.dbo.#ECG_MatchTypeExclusions') IS NOT NULL
    DROP TABLE #ECG_MatchTypeExclusions
  IF OBJECT_ID('tempdb.dbo.#ECG_Spelling') IS NOT NULL
    DROP TABLE #ECG_Spelling
  IF OBJECT_ID('tempdb.dbo.#ECG_QuantitativeMatch') IS NOT NULL
    DROP TABLE #ECG_QuantitativeMatch
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosisMatch') IS NOT NULL
    DROP TABLE #ECG_DiagnosisMatch
  IF OBJECT_ID('tempdb.dbo.#ECG_Misspellings') IS NOT NULL
    DROP TABLE #ECG_Misspellings


GO
/****** Object:  StoredProcedure [dbo].[ECG_DetermineEpicECGIdentifiers]    Script Date: 6/29/2021 5:28:01 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/*
ECG_DetermineEpicECGIdentifiers

Determine the ORDER_TYPE_C and the PROC_ID for the ECG narratives in Epic

The values for the ORDER_TYPE_C adn PROC_ID need to be applied to the PROC ECG_LoadNarratives


Modify the proc as needed to select the ECG's to include in the processing

Author: Richard H. Epstein, MD
Copyright (C) 2020

Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding


*/


--*/
CREATE PROC [dbo].[ECG_DetermineEpicECGIdentifiers]
AS
  --*/

  SET NOCOUNT ON

  -- NOTE: Change the name of the database from CLARITY to the location on your system

  -- **********************************************************
  -- * 1. Determine the order_type_c of the ECG tests in Epic
  -- **********************************************************
  SELECT
    *
  FROM CLARITY.[dbo].[ZC_ORDER_TYPE] WITH (NOLOCK)
  WHERE name LIKE '%e[ck]g%'

  -- **********************************************************
  -- * 2. Determine the proc_id of the potential ECG narratives
  -- **********************************************************
  SELECT
    PROC_ID,
    Description,
    COUNT(PROC_ID) AS n
  FROM CLARITY.dbo.ORDER_PROC WITH (NOLOCK)
  WHERE ORDER_TYPE_C IN (28, 62)  -- modify this list from the previous step
  AND
  (
  Description LIKE '%e[ck]g%'
  OR Description LIKE '%electrocard%'
  )
  GROUP BY PROc_ID,
           DESCRIPTION
  ORDER BY n DESC

  -- *************************************************************
  -- * 3. Check the PROC_IDs from step 2 above to determine which are 
  -- * actually ECG narratives from 12 lead ECG reports
  -- ************************************************************
  SELECT TOP 100
    a.ORDER_PROC_ID,
    a.description,
    line,
    ISNULL(Narrative, '') AS Narrative
  FROM CLARITY.dbo.order_proc a WITH (NOLOCK)
  INNER JOIN CLARITY.dbo.ORDER_NARRATIVE b WITH (NOLOCK)
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE PROC_ID IN (509)					-- modify this number by the candidate PROC_IDs from step 2, above
  ORDER BY PROC_ID,
  a.ORDER_PROC_ID,
  b.line



GO
/****** Object:  StoredProcedure [dbo].[ECG_IdentifyMisspelledWords]    Script Date: 6/29/2021 5:28:01 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/*
ECG_IdentifyMisspelledWords

Identified words in the EKG narratives that are misspelled by matching to the ecg_spelling table
and the misspelling table This will identify new misspelled words that should be added to the tab-delimited file ECG_Misspellings.txt

Words that are spelled correctly shoulde be added to the tab-delimited file ECG_Spelling.txt
Then reimport the configuration files using the stored procedure [dbo].[ECG_CreateTablesForNLProcessing]

Author: Richard H. Epstein, MD
Copyright (C) 2020


Date		Ver		By		Comment
09/11/20	1.00	RHE		Initial Coding
01/13/21	2.00	RHE		Code for distribution in Google drive



*/

CREATE PROC [dbo].[ECG_IdentifyMisspelledWords]
AS

  SET NOCOUNT ON

  -- **************************
  -- 05/14/19 RHE break out the narratives to all words so can check spelling errors 
  -- do not consider narrative with Test Reason as those are not used in the algorithm and the source of most spelling errors
  -- I used NLTK toolkit to generate a dictionary of words in dbo.Spelling
  -- these included several online ECG tutorial and the websters unabrideged dictionary
  -- **************************

  IF OBJECT_ID('tempdb.dbo.#Sentences') IS NOT NULL
    DROP TABLE #Sentences
  IF OBJECT_ID('tempdb.dbo.#SingleWords') IS NOT NULL
    DROP TABLE #SingleWords
  IF OBJECT_ID('tempdb.dbo.#UniqueWords') IS NOT NULL
    DROP TABLE #UniqueWords
  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#WordsToCheckSpelling') IS NOT NULL
    DROP TABLE #WordsToCheckSpelling

  CREATE TABLE #Sentences (
    idx int IDENTITY (1, 1),
    narrative varchar(1024)
  )
  CREATE TABLE #SingleWords (
    idx int IDENTITY (1, 1),
    word varchar(255)
  )
  CREATE TABLE #UniqueWords (
    word varchar(255),
    n int
  )
  CREATE TABLE #EKG (
    idx int IDENTITY (1, 1),
    Narrative varchar(1024)
  )
  CREATE TABLE #WordsToCheckSpelling (
    word varchar(100)
  )


  TRUNCATE TABLE #EKG

  INSERT INTO #EKG
    SELECT DISTINCT
      narrativeraw
    FROM dbo.ECG_Narratives
    WHERE ignore = 0

  TRUNCATE TABLE #Sentences
  INSERT INTO #sentences
    SELECT
      LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(narrative, '        ', ' '), '       ', ' '), '      ', ' '), '    ', ' '), '   ', ' '), '  ', ' '), '  ', ' '), '  ', ' '), '"', ' ')))
    FROM #EKG

  UPDATE #Sentences
  SET narrative =
  REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE
  (narrative, '.', ' '), ',', ' '), ';', ' '), '/', ' '), '  ', ' '), '(', ' '), ')', ' '), '[', ' '), ']', ' '), '\', ''), '"', ' '), '*', ' '), '+', ' '), '>', ' '), '<', ' '), '=', ' '), '?', ' '), '~', ' '), '!', ' '), '''', ' ')


  -- *******************************
  DECLARE @nWordsLeft int = (SELECT
    COUNT(idx)
  FROM #Sentences
  WHERE CHARINDEX(' ', narrative) > 0)
  TRUNCATE TABLE #SingleWords


  WHILE @nWordsLeft > 0
  BEGIN
    INSERT INTO #SingleWords
      SELECT
        CASE
          WHEN CHARINDEX(' ', Narrative) = 0 THEN Narrative
          ELSE SUBSTRING(narrative, 1, CHARINDEX(' ', Narrative) - 1)
        END
      FROM #Sentences
      WHERE LEN(narrative) > 0

    UPDATE #Sentences
    SET narrative = SUBSTRING(narrative, CHARINDEX(' ', Narrative) + 1, 255)

    SELECT
      @nWordsLeft = (SELECT
        COUNT(idx)
      FROM #Sentences
      WHERE CHARINDEX(' ', narrative) > 0)
    DELETE FROM #Sentences
    WHERE LEN(narrative) = 0
  END


  -- when get to the end there will be single words left in the #Sentences tables wwith no spaces. add them
  INSERT INTO #SingleWords
    SELECT
      narrative
    FROM #Sentences

  -- get rid of . and , and other punctution marks
  UPDATE #SingleWords
  SET word = REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(word, '.', ' '), ',', ' '), ';', ' '), '/', ' '), '  ', ' '), '(', ' '), ')', ' '), '[', ' '), ']', ' '), '\', '')


  TRUNCATE TABLE #UniqueWords
  INSERT INTO #UniqueWords
    SELECT
      LTRIM(RTRIM(word)),
      COUNT(word) AS n
    FROM #SingleWords
    GROUP BY LTRIM(RTRIM(word))
    ORDER BY n DESC



  TRUNCATE TABLE #WordsToCheckSpelling
  INSERT INTO #WordsToCheckSpelling
    SELECT DISTINCT
      word
    FROM #UniqueWords
    WHERE LEN(word) > 4
    AND word NOT LIKE '%:%'
    AND word NOT LIKE '%[0-9][0-9]-%'
    AND word NOT LIKE '%/%/%'
    AND word NOT LIKE '%-%-%'
    AND word NOT LIKE '%[0-9][0-9][0-9][0-9]%'
    AND word NOT LIKE '%/%'
    ORDER BY word

  -- replace words starting with a -
  UPDATE #WordsToCheckSpelling
  SET word = REPLACE(word, '-', '')
  WHERE SUBSTRING(word, 1, 1) = '-'

  -- remove words in the spelling table. these are ok
  DELETE FROM #WordsToCheckSpelling
    FROM #WordsToCheckSpelling a
    INNER JOIN dbo.ecg_spelling b
      ON a.word = b.word



  -- remove words already in the misspelling table. 
  DELETE FROM #WordsToCheckSpelling
    FROM #WordsToCheckSpelling a
    INNER JOIN dbo.ecg_misspellings b
      ON a.word = b.bad

  -- remove words that are dates or start with numbers
  DELETE FROM #WordsToCheckSpelling
    FROM #WordsToCheckSpelling
  WHERE word LIKE '%[0-9][ /][0-9]%[ /][0-9][0-9]%'
    OR word LIKE '[0-9]%'

  -- words to check and supply corrected spelling
  SELECT
    word
  FROM #WordsToCheckSpelling




  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#Sentences') IS NOT NULL
    DROP TABLE #Sentences
  IF OBJECT_ID('tempdb.dbo.#SingleWords') IS NOT NULL
    DROP TABLE #SingleWords
  IF OBJECT_ID('tempdb.dbo.#UniqueWords') IS NOT NULL
    DROP TABLE #UniqueWords
  IF OBJECT_ID('tempdb.dbo.#WordsToCheckSpelling') IS NOT NULL
    DROP TABLE #WordsToCheckSpelling







GO
/****** Object:  StoredProcedure [dbo].[ECG_LoadNarratives_Epic]    Script Date: 6/29/2021 5:28:01 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
ECG_LoadNarratives_Epic

Description:
	Load the ECG narratives into the table dbo.ECG_Narratives FROM Epic
	If using an EHR other than Epic, the table dbo.ECG_Narratives needs to be loaded using code for that system or from a tab delimited text file
	using the stored procedure ECG_LoadNarratives_Text

Author: Richard H. Epstein, MD
Copyright (C) 2020


IMPORTANT NOTES: 
	1. Modify the values PROC_ID as determined FROM the stored procedure ECG_Epic_Find_PROC_ID
	2. Modify the values of @StartDate and @EndDate to SELECT the desired range of ECG narratives to process
	3. The NarrativeRaw will be processed subsequently by the stored procedure ECG_PreprocessNarratives to create the Narrative field
 
Syntax:
	EXEC [dbo].[ECG_LoadNarratives]									-- load ECG narrative from the previous 60 days
	EXEC [dbo].[ECG_LoadNarratives] '2019-01-01', '2019-12-31'		-- load ECG narratives from the specified date range


Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding



*/


--/*
CREATE PROC [dbo].[ECG_LoadNarratives_Epic] @StartDate datetime = NULL, @EndDate datetime = NULL
AS

  SET NOCOUNT ON

  --*/

-- NOTE: Change CLARITY to the database on your system where the Clarity tables are stored


  /*  -- uncomment to run manually and specifiy the date values
  DECLARE @StartDate datetime		= '2019-01-01'
  DECLARE @EndDate datetime		= '2019-12-31'
  --*/

  -- if no date parameter is supplied, default to the most recent 30 days
  IF @EndDate IS NULL
  BEGIN
    SET @EndDate = GETDATE()
  END							-- default to current date if null
  IF @StartDate IS NULL
  BEGIN
    SET @StartDate = DATEADD(dd, -60, @EndDate)
  END					-- default to 60 days before @EndDate if null



  -- Retrieve the ECG narratives into a database table after clearing the data in that table
  TRUNCATE TABLE dbo.ECG_Narratives
  INSERT INTO dbo.ECG_Narratives
    SELECT
      pat_id,
      a.ORDER_PROC_ID,
      b.contact_date,
      a.description,
      line,
      NULL AS Narrative,
      RTRIM(LTRIM(ISNULL(Narrative, ''))) AS NarrativeRaw,  -- get rid of any leading or trailing spaces on each line
      0 AS ignore
    FROM CLARITY.DBO.ORDER_PROCx a WITH (NOLOCK)
    INNER JOIN CLARITY.DBO.ORDER_NARRATIVE b WITH (NOLOCK)
      ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    WHERE
    -- NOTE: Modify the list of PROC_ID and ORDER_TYPE_C below to correspond to your version of Epic
    (
    ORDER_TYPE_C IN (28, 62)
    AND PROC_ID IN (509, 21000000009, 92916, 515, 178113)
    )
    AND CONTACT_DATE BETWEEN @StartDate AND @EndDate
    ORDER BY a.pat_id,
    a.ORDER_PROC_ID,
    b.line





GO
/****** Object:  StoredProcedure [dbo].[ECG_LoadNarratives_Text]    Script Date: 6/29/2021 5:28:01 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

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







GO
/****** Object:  StoredProcedure [dbo].[ECG_PreProcessNarratives]    Script Date: 6/29/2021 5:28:01 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
ECG_PreProcessNarratives

Description:
	Correct spelling mistakes in the dbo.ECG_Narratives table NarrativeRaw field and copy to the Narrative field

 
Author: Richard H. Epstein, MD
Copyright (C) 2020


IMPORTANT NOTES: 

Syntax:
	EXEC dbo.ECG_PreProcessNarratives	
	
	
Performance:
	240 sec for 56177 ECG	4.27 msec/EKG   
	



Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding
01/21/20	1.01	RHE		Performance improvements


*/

--/*
CREATE PROC [dbo].[ECG_PreProcessNarratives]
AS
  --*/

  SET NOCOUNT ON

  -- *************************************************************************************
  -- *** determine what words are misspelled in the EKG narratives and then correct them
  -- *************************************************************************************

  IF OBJECT_ID('tempdb.dbo.#Corrections') IS NOT NULL
    DROP TABLE #Corrections
  IF OBJECT_ID('tempdb.dbo.#Misspellings') IS NOT NULL
    DROP TABLE #Misspellings


  CREATE TABLE #Misspellings (
    IDX int IDENTITY,
    word varchar(255),
    correction varchar(255)
  )

  CREATE TABLE #Corrections (
    IDXcorrection int IDENTITY (1, 1),
    idx int,
    narrative varchar(255),
    narrative_corrected varchar(1024),
    bad varchar(255),
    good varchar(255),
    Processed tinyint
  )

  -- select top 100 * from dbo.ECG_Narratives

  -- ****************************************
  -- eliminate lines from the dbo.ECG_Narratives table that are blank or empty
  -- ****************************************
  DELETE FROM dbo.ECG_Narratives
  WHERE RTRIM(ISNULL(NarrativeRaw, '')) = ''

  -- ****************************************
  -- * copy narrative raw to narrative
  -- * Get rid of superfluous punctuation, and double spaces 
  -- * add a space at the start and end of each line to allow the matching to not have to deal with the word boundary issue for 
  -- * misspelled words at the start and end of the line
  -- * Punctuation replaced with single space: ,.;!?" and tab
  -- * 1/21/21 RHE
  -- ****************************************

  UPDATE dbo.ECG_Narratives
  SET Narrative =
      REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(NarrativeRaw, ',', ' '), ';', ' '), '!', ' '), '?', ' '), CHAR(9), ' '), '"', ' '), '.', ' '),
      Ignore = 0


  -- get rid of empty lines after removing punctuation
  DELETE FROM dbo.ECG_Narratives
  WHERE RTRIM(ISNULL(Narrative, '')) = ''

  -- insert a space at the start and end of each narrative to avoid word boundry issues at the start and end of each line
  UPDATE dbo.ECG_Narratives
  SET Narrative = ' ' + Narrative + ' '




  -- ******************************************************
  -- * Find the words in the misspelling table that are present in the narratives
  -- ******************************************************
  TRUNCATE TABLE #Misspellings

  INSERT INTO #Misspellings
    SELECT DISTINCT
      bad,
      good
    FROM dbo.ECG_Misspellings a,
         (SELECT DISTINCT
           Narrative
         FROM dbo.ECG_Narratives) x
    WHERE CHARINDEX(bad, Narrative) > 0

  TRUNCATE TABLE #Corrections

  DECLARE @sql2 nvarchar(1024)
  DECLARE @nMisspelled int = (SELECT
    MAX(idx)
  FROM dbo.ECG_Misspellings)

  DECLARE @nn int = 1
  DECLARE @good varchar(100)
  DECLARE @bad varchar(100)


  -- regex expressions below account for word boundry issues
  WHILE @nn <= @nMisspelled
  BEGIN
    SET @good = (SELECT
      REPLACE(correction, '''', '''''')
    FROM #Misspellings
    WHERE idx = @nn)
    SET @bad = (SELECT
      REPLACE(word, '''', '''''')
    FROM #Misspellings
    WHERE idx = @nn)

    SELECT
      @SQL2 =
      N'
	insert into #Corrections (idx, narrative,  narrative_corrected, bad, good) 
	select distinct 
	idx, 
	Narrative, 
	replace(Narrative, ''' + @bad + ''' , ''' + @good + ''' ),'''
      + @bad + ''',''' + @good + ''' 
	from dbo.ECG_Narratives
	where
	( 
		Narrative like ''% ' + @bad + ' %''
	) 
	'

    EXEC sp_executesql @SQL2

    -- make corrections each pass beacuse there can be multiple errors in the same line
    UPDATE dbo.ECG_Narratives
    SET NARRATIVE = B.narrative_corrected
    FROM dbo.ECG_Narratives a
    INNER JOIN #Corrections b
      ON a.idx = b.idx
    WHERE b.processed IS NULL

    UPDATE #Corrections
    SET processed = 1
    WHERE processed IS NULL

    SET @nn = @nn + 1
  END



  -- *************************************
  -- * Get rid of leading and trailing spaces that previously were added
  -- **************************************
  UPDATE dbo.ECG_Narratives
  SET Narrative = LTRIM(RTRIM(Narrative))



  -- *********************************
  -- * get rid oF double spaces
  -- *********************************
  DECLARE @nRows integer = 1

  WHILE @nRows > 0
  BEGIN
    UPDATE dbo.ECG_Narratives
    SET Narrative = REPLACE(REPLACE(narrative, '   ', ' '), '  ', ' ')
    WHERE CHARINDEX('  ', narrative) > 0

    SET @nRows = @@ROWCOUNT
  END


  -- *******************************************************************************
  -- mark rows to ignore with a 0 that are not diagnoses and should not be processed
  -- mark rows that will be processed as quantitative data with a 2
  -- ********************************************************************************
  -- These are rows with quantitative information
  UPDATE dbo.ECG_Narratives
  SET ignore = 2
  FROM dbo.ECG_Narratives a, dbo.ECG_QuantitativeMatch b
  WHERE CHARINDEX(b.MatchString, a.narrative) > 0
  AND a.ignore = 0

  -- these are rows with non-diagnostic and non-quantitative data
  UPDATE dbo.ECG_Narratives
  SET ignore = 1		-- 
  FROM dbo.ECG_Narratives a, dbo.ECG_DiagnosisExclusions b
  -- 02/17/21 RHE force exclusion to start the line
  WHERE CHARINDEX(b.phrase, a.narrative) = 1
  AND a.ignore = 0


  UPDATE dbo.ECG_Narratives
  SET Ignore = 1
  FROM dbo.ECG_Narratives a, dbo.ECG_MatchTypeExclusion b
  WHERE CHARINDEX(b.ExcludeMatchString, a.narrative) > 0
  AND a.ignore = 0
  AND matchType = 2


  -- get rid of signature names that are not preced by reviewed by, etc.
  UPDATE dbo.ECG_Narratives
  SET Ignore = 1
  WHERE narrative LIKE '%/%/%:%[AP]M%'   -- these have dates and timesa datetime
  AND IGNORE = 0


  -- 02/20/21 If you want to include all rows for processing, not excluding as above, uncomment the next line
  -- UPDATE dbo.ECG_Narratives SET Ignore = 0

  -- If the word versus, vs or vs. is present, then replace it with possible and add possible at the start of the narrative
  UPDATE dbo.ECG_Narratives
  SET narrative = 'Possible ' + narrative
  WHERE (narrative LIKE '%versus%'
  OR narrative LIKE '% vs %'
  OR narrative LIKE '% vs. %')
  AND narrative NOT LIKE 'Cannot%'
  AND narrative NOT LIKE 'Possib%'
  AND narrative NOT LIKE 'Probab%'
  AND narrative NOT LIKE 'Test %'
  AND ignore = 0


  UPDATE dbo.ECG_Narratives
  SET narrative = REPLACE(Narrative, ' versus', ' versus Possible ')
  UPDATE dbo.ECG_Narratives
  SET narrative = REPLACE(Narrative, ' vs ', ' versus Possible ')
  UPDATE dbo.ECG_Narratives
  SET narrative = REPLACE(Narrative, ' vs. ', ' versus Possible ')


  IF OBJECT_ID('tempdb.dbo.#Corrections') IS NOT NULL
    DROP TABLE #Corrections
  IF OBJECT_ID('tempdb.dbo.#Misspellings') IS NOT NULL
    DROP TABLE #Misspellings


GO
/****** Object:  StoredProcedure [dbo].[ECG_ProcessNarratives]    Script Date: 6/29/2021 5:28:01 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


/*
ECG_ProcessNarratives

Process the ECG narratives in the table dbo.ECG_Narratives and saves results into table dbo.ECG_DiagnosticInfo

Author: Richard H. Epstein, MD
Copyright (C) 2020

Syntax
	EXEC dbo.ECG_ProcessNarratives		-- process the narratives and produce the dbo.ECG_ResultsQuantitative and dbo.ECG_ResultsDiagnosis tables
	EXEC dbo.ECG_ProcessNarratives 0	-- same as with no parameter suplied
	EXEC dbo.ECG_ProcessNarratives 1	-- process the narratives as above and also generate the additional tables to evaluate performance of the algorithm
						
						
Examine the input file
	Select * from dbo.ECG_Narratives										

Examine the quantitative and diagnosis output tables
	Select top 100 * from dbo.ECG_ResultsQuantitative			-- quantitative values from the ECG narratives
	Select top 100 * from dbo.ECG_ResultsDiagnostic				-- diagnostic information from the ECG narratives

Examine the performance output tables
	Select  * from [dbo].[ECG_PerformanceAllNarratives]							-- 
	Select top 100 * from [dbo].[ECG_PerformanceDiscreteNarratives]				--	
	Select top 100 * from [dbo].[ECG_PerformanceNarrativesWithoutDiagnosis]		-- narrative lines that did not match to a diagnosis


Instructions
1.	Execute the proc dbo.ECG_CreateTablesForNLProcessing to create the tables needed for processing
2.  If using Epic
	Execute the proc ECG_DetermineEpicECGIdentifiers to determine the relevant values of ORDER_TYPE_C and PROC_iD
	Modify dbo.ECG_LoadNarratives to use the local Epic values
3.	If using Epic	
	Execute dbo.ECG_LoadNarratives to insert the ECG narratives into the table dbo.ECG_Narratives
	If not using Epic
	Load the ECG narratives into the table dbo.ECG_Narratives using your own procedure
3.	Exec dbo.ECG_IdentifiedMisspelledWords and add misspelled word mappings into the table dbo.ECG_MisspelledWords
4.  Change the value of @MaxLineLength as necessary in the stored procedure and then execute the code to alter the procedure. Default is 130 for the MUSE system
5.  Execute the current procedure dbo.ECG_ProcessNarratives to extract the diagnostic and quantitative information from the ECG narratives


select top 100 * from dbo.ECG_Narratives order by ORDER_PROC_ID, linenumber
select top 100 * from dbo.ECG_ResultsQuantitative order by ORDER_PROC_ID
select top 100 * from dbo.ECG_ResultsDiagnostic order by ORDER_PROC_ID, Diagnosis

Date		Ver		By		Comment
09/12/20	1.00	RHE		Initial Coding
01/13/20	2.00	RHE		Modified code for distribution in the Google drive folder
01/20/21	2.01	RHE		Moved code to preprocess the narratitve into dbo.ECG_Preprocessnarratives. Removed coresponding code here
							This will allow more rapid modification of the configuraiton tables for diagnosis processing	
02/24/21	2.02	RHE		Modified code for processing complex lines excluding historical diagnoses to include ' however '
*/

--/*
CREATE PROC [dbo].[ECG_ProcessNarratives] @EvaluatePerformance tinyint = 0
AS
  --*/

  SET NOCOUNT ON

  /*
  DECLARE @EvaluatePerformance tinyint = 1 -- 1= generate the output for analysis of the processing;  0=skip the analysis (for production use)
  --*/


  /* --for performance evaluation
  declare @Time1 datetime, @Time2 datetime
  set @Time1 = getdate()
  */


  -- **************************************************
  -- Set the max number of characters to determine if the line is continued
  -- **************************************************
  DECLARE @MaxLineLength smallint = 130

  IF OBJECT_ID('tempdb.dbo.#EKGSummary') IS NOT NULL
    DROP TABLE #EKGSummary
  IF OBJECT_ID('tempdb.dbo.#DiagnosisExclusions') IS NOT NULL
    DROP TABLE #DiagnosisExclusions
  IF OBJECT_ID('tempdb.dbo.#HedgePhrases') IS NOT NULL
    DROP TABLE #HedgePhrases
  IF OBJECT_ID('tempdb.dbo.#QuantitativeMatch') IS NOT NULL
    DROP TABLE #QuantitativeMatch
  IF OBJECT_ID('tempdb.dbo.#MatchTypeExclusion') IS NOT NULL
    DROP TABLE #MatchTypeExclusion
  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosesNoLongerPresent') IS NOT NULL
    DROP TABLE #ECG_DiagnosesNoLongerPresent
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluation') IS NOT NULL
    DROP TABLE #DiagnosisEvaluation
  IF OBJECT_ID('tempdb.dbo.#EKG_Quantitative') IS NOT NULL
    DROP TABLE #EKG_Quantitative
  IF OBJECT_ID('tempdb.dbo.#EKGSummary') IS NOT NULL
    DROP TABLE #EKGSummary
  IF OBJECT_ID('tempdb.dbo.#SQL') IS NOT NULL
    DROP TABLE #SQL
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluationHedged') IS NOT NULL
    DROP TABLE #DiagnosisEvaluationHedged
  IF OBJECT_ID('tempdb.dbo.#Performance') IS NOT NULL
    DROP TABLE #Performance
  IF OBJECT_ID('tempdb.dbo.#UniqueNarratives') IS NOT NULL
    DROP TABLE #UniqueNarratives

  -- hedge phrases
  CREATE TABLE #DiagnosisEvaluationHedged (
    IDX int,
    PAT_ID varchar(18),
    ORDER_PROC_ID decimal(18, 0),
    ECGDate datetime,
    NarrativeRaw varchar(1024),
    Narrative varchar(1024),
    Code char(3),
    Diagnosis varchar(100),
    DiagnosisUncertain tinyint,
    MatchLocation int,
    Ignore tinyint,
    HedgeCode char(3),
    HedgePhrase varchar(30),
    HedgeLocation int
  )


  -- match diagnoses
  CREATE TABLE #DiagnosisEvaluation (
    IDX int IDENTITY (1, 1),
    PAT_ID varchar(18),
    ORDER_PROC_ID decimal(18, 0),
    ECGDate datetime,
    NarrativeRaw varchar(1024), -- -2/18/21 RHE add here so can have the original line
    Narrative varchar(1024),
    Code char(3),
    Diagnosis varchar(100),
    DiagnosisUncertain tinyint,	-- if diagnosis is preceded by a hedge word such as possible, cannot rule out, cannot exclude, etc
    MatchLocation int,
    Ignore tinyint
  )

  -- summary table for quantitative assessment of EKG
  CREATE TABLE #EKGSummary (
    pat_id varchar(18),
    ORDER_PROC_ID numeric(18),
    EKGDate datetime,
    Description varchar(30),
    Indication varchar(100),
    QT smallint,
    P_Axis smallint,
    R_Axis smallint,
    T_Axis smallint,
    QRS smallint,
    PR smallint,
    QTc smallint,
    V_Rate smallint,
    A_Rate smallint,
    Interpreter varchar(255),
    InterpretationTime datetime
  )

  -- phrases to exclude from processing diagnoses, as these are quantitative or non-diagnostic (administrative) info
  CREATE TABLE #DiagnosisExclusions (
    Phrase varchar(100)
  )

  CREATE TABLE #HedgePhrases (
    code char(3),
    phrase varchar(30)
  )

  -- specifications for the quantitative information at the top of the ECG narrative
  CREATE TABLE #QuantitativeMatch (
    MatchType smallint,
    MatchString varchar(100), --	string to search for
    VariableName varchar(60), --	name of the value to report
    Offset smallint,		  --	offset # of chars from the start of the match string to the first character/digit of the value
    StringLength smallint,	  --    number of characters in the value; 999 means rest of the line
    Allow0 tinyint,			  --	if 0 means that a value of 0 is not allowed and will be replaced with a null if empty; 1 means the value can be empty
    StringValue tinyint		  --    1 means that the value is a string; 0 an integer
  )

  -- insert exclusions here that apply to all matches of same type
  -- 1 = diagnostic criterion
  CREATE TABLE #MatchTypeExclusion (
    MatchType smallint,
    ExcludeMatchString varchar(100)
  )

  -- table for processing the ECGs
  CREATE TABLE #EKG (
    idx int IDENTITY (1, 1),
    PAT_ID varchar(18),
    ORDER_PROC_ID varchar(18),
    contact_date datetime,
    Description varchar(255),
    line int,
    Narrative varchar(1024),
    NarrativeRaw varchar(1024),
    Ignore tinyint
  )

  CREATE TABLE #ECG_DiagnosesNoLongerPresent (
    IDX int IDENTITY (1, 1),
    ReplacementType varchar(6),
    Phrase varchar(100)
  )

  TRUNCATE TABLE #DiagnosisExclusions
  INSERT INTO #DiagnosisExclusions
    SELECT
      Phrase
    FROM dbo.ECG_DiagnosisExclusions
    ORDER BY IDX
  -- select * from #DiagnosisExclusions

  TRUNCATE TABLE #HedgePhrases
  INSERT INTO #HedgePhrases
    SELECT
      CODE,
      Phrase
    FROM dbo.ECG_HedgePhrases
    ORDER BY IDX
  -- select * from #HedgePhrases

  TRUNCATE TABLE #QuantitativeMatch
  INSERT INTO #QuantitativeMatch
    SELECT
      MatchType,
      MatchString,
      VariableName,
      Offset,
      StringLength,
      Allow0,
      StringValue
    FROM dbo.ECG_QuantitativeMatch
    ORDER BY IDX
  -- select * from #QuantitativeMatch

  -- insert exclusions here that apply to all matches of same type
  -- match types
  -- 1 = diagnostic criterion

  -- drop table #MatchTypeExclusion
  TRUNCATE TABLE #MatchTypeExclusion
  INSERT INTO #MatchTypeExclusion
    SELECT
      MatchType,
      ExcludeMatchString
    FROM dbo.ECG_MatchTypeExclusion
    ORDER BY IDX
  --select * from #MatchTypeExclusion

  -- *********************************************
  -- * Load  ECG narratives from the table dbo.ECG_Narratives
  -- * This table has already been processed to fix spelling errors
  -- * so the field narrative has the corrected strings
  -- *********************************************
  TRUNCATE TABLE #EKG
  INSERT INTO #EKG
    SELECT
      PATIENT_ID,
      ORDER_PROC_ID,
      ECGDate,
      ECGDescription,
      LineNumber,
      Narrative AS Narrative,
      NarrativeRaw AS NarrativeRaw,
      ignore
    FROM dbo.ECG_Narratives
    WHERE narrative IS NOT NULL
    ORDER BY PATIENT_ID,
    ORDER_PROC_ID,
    LineNumber

  TRUNCATE TABLE #ECG_DiagnosesNoLongerPresent
  INSERT INTO #ECG_DiagnosesNoLongerPresent
    SELECT
      ReplacementType,
      Phrase
    FROM dbo.ECG_DiagnosesNoLongerPresent
    ORDER BY IDX
  -- select * from #ECG_DiagnosesNoLongerPresent


  -- narratives are continued on the next line if the len>150 so combine if len=150 and first char of next line is not a capital
  -- if need to explore the length, uncomment the next line and change the value of @MaxLineLength
  -- declare @MaxLineLength smallint = 130

  UPDATE a
  SET a.narrative = RTRIM(a.narrative) + ' ' + LTRIM(b.narrative)
  FROM #EKG a
  INNER JOIN #EKG b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    AND a.line = b.line - 1
  WHERE LEN(a.narrative) >= @MaxLineLength
  AND (ASCII(SUBSTRING(LTRIM(b.narrative), 1, 1)) NOT BETWEEN 65 AND 90)  -- skip upper case first letters

  -- delete the narrative where the line is a continuation line, as from the previous block
  UPDATE b
  SET b.narrative = ''
  FROM #EKG a
  INNER JOIN #EKG b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    AND a.line = b.line - 1
  WHERE LEN(a.narrative) >= @MaxLineLength
  AND (ASCII(SUBSTRING(LTRIM(b.narrative), 1, 1)) NOT BETWEEN 65 AND 90)  -- skip upper case first letters


  -- ************************************************************************************************************
  -- 02/17/21 RHE New code to handle mixing of new and old diagnoses on the same line, as done at VUMC but not UM
  -- ************************************************************************************************************
  DECLARE @ReplacementType varchar(6),
          @Phrase varchar(100),
          @SQL nvarchar(2048)
  DECLARE @ii smallint = 1
  DECLARE @iiMax smallint = (SELECT
    MAX(IDX)
  FROM #ECG_DiagnosesNoLongerPresent)

  WHILE @ii <= @iiMax
  BEGIN
    SET @ReplacementType = (SELECT
      ReplacementType
    FROM #ECG_DiagnosesNoLongerPresent
    WHERE idx = @ii)
    SET @Phrase = (SELECT
      Phrase
    FROM #ECG_DiagnosesNoLongerPresent
    WHERE idx = @ii)

    IF @ReplacementType IS NOT NULL
    BEGIN
      SET @SQL =
                CASE
                  WHEN @ReplacementType = 'After' THEN 'update #EKG
				set narrative =
				substring(narrative, 1, charindex(''' + @Phrase + ''',narrative)-1) 
				+
				case
					when charindex('' however '',narrative)>0 then
						case
							when charindex('' however '', narrative) > charindex(''' + @Phrase + ''',narrative)  
								then substring(Narrative, charindex('' however '',Narrative)+1,255)
							else ''''
						end
					when charindex('' but '',narrative)>0 then
						case
							when charindex('' but '', narrative) > charindex(''' + @Phrase + ''',narrative)  
								then substring(Narrative, charindex('' but '',Narrative)+1,255)
							else ''''
						end
					when charindex('' and '',narrative)>0 then
						case
							when charindex('' and '', narrative) > charindex(''' + @Phrase + ''',narrative)  
								then substring(Narrative, charindex('' and '',Narrative)+1,255)
							else ''''
						end

					else ''''
				end 
			where narrative like ''%' + @Phrase + '%''
			'

                  WHEN @ReplacementType = 'Before' THEN 'update #EKG
				set narrative =
				case
					when charindex('' however '',narrative)>0 or charindex('' but '',narrative)>0 or charindex('' and '',narrative)>0 then 
						case
							when (charindex('' but '', narrative) >0) AND (charindex('' but '', narrative) < charindex(''' + @Phrase + ''',narrative))   
								then substring(Narrative, 1, charindex('' but '',Narrative) -1) 	
							when (charindex('' however '', narrative)>0) AND (charindex('' however '', narrative) < charindex(''' + @Phrase + ''',narrative))   
								then substring(Narrative, 1, charindex('' however '',Narrative) -1) 
							when (charindex('' and '', narrative)>0) AND (charindex('' and '', narrative) < charindex(''' + @Phrase + ''',narrative))   
								then substring(Narrative, 1, charindex('' and '',Narrative) -1) 
							else ''''
						end
					else ''''
				end
				+
				substring(narrative, charindex(''' + @Phrase + ''',narrative) + len(''' + @Phrase + '''), 255 )
				from #EKG 
				where narrative like ''%' + @Phrase + '%''
				'
                  ELSE NULL
                END

      IF @SQL IS NOT NULL
      BEGIN
        EXEC (@SQL)
      END
    END
    SET @SQL = NULL
    SET @ii = @ii + 1
  END


  -- ***************************************************************************************************************
  -- ***************************************************************************************************************

  CREATE TABLE #EKG_Quantitative (
    ORDER_PROC_ID varchar(18),
    Line smallint,
    Narrative varchar(255),
    MatchString varchar(100),
    VariableName varchar(30),
    NumericValue int,
    StringValue varchar(1024)
  )

  -- ************************************
  --- determine the quantitative values
  -- ************************************
  TRUNCATE TABLE #EKG_Quantitative
  INSERT INTO #EKG_Quantitative
    SELECT
      ORDER_PROC_ID,
      Line,
      Narrative,
      MatchString,
      VariableName,
      CASE
        WHEN x.StringValue = 1 THEN NULL
        WHEN x.Allow0 = 1 THEN CONVERT(smallint, x.value)
        WHEN CONVERT(smallint, x.value) = 0 THEN NULL
        ELSE CONVERT(smallint, x.value)
      END AS NumericValue,
      CASE
        WHEN x.StringValue = 1 THEN Value
        ELSE NULL
      END AS StringValue
    FROM (SELECT
      ORDER_PROC_ID,
      Line,
      Narrative,
      b.MatchString,
      SUBSTRING(Narrative, CHARINDEX(b.matchstring, narrative) + offset, b.StringLength) AS value,
      c.ExcludeMatchString,
      CHARINDEX(c.excludematchstring, narrative) AS n,
      VariableName,
      Allow0,
      StringValue
    FROM #EKG a,
         #QuantitativeMatch b
         LEFT JOIN #MatchTypeExclusion c
           ON b.MatchType = c.MatchType
    WHERE ignore = 2			-- during preprocessing, rows with quantitative info are marked with a 2
    AND CHARINDEX(b.MatchString, a.Narrative) > 0
    --order by value desc -- ORDER_PROC_ID, MatchString
    ) x
    GROUP BY ORDER_PROC_ID,
             Line,
             Narrative,
             MatchString,
             VariableName,
             value,
             Allow0,
             StringValue
    HAVING SUM(n) = 0
    ORDER BY ORDER_PROC_ID, line
  -- select top 100 * from  #EKG_Quantitative

  -- extract the summary information for each order for the quantitative information
  TRUNCATE TABLE #EKGSummary
  INSERT INTO #EKGSummary (pat_id,
  ORDER_PROC_ID,
  EKGDate,
  Description)
    SELECT DISTINCT
      pat_id,
      ORDER_PROC_ID,
      Contact_Date,
      Description
    FROM #EKG

  -- apply the quantitative values
  DECLARE @TestReason varchar(30) = (SELECT
    MatchString
  FROM #QuantitativeMatch
  WHERE VariableName = 'Test_Reason')

  -- get the indication for the test and who reviewed it
  UPDATE #EKGSummary
  SET Indication = RTRIM(REPLACE(Narrative, @TestReason, ''))
  FROM #EKGSummary a
  INNER JOIN #EKG b
    ON a.order_proc_id = b.ORDER_PROC_ID
  WHERE CHARINDEX(@TestReason, Narrative) = 1


  -- if there is no test reason listed, just 'Test Reason :' set this to ;;
  UPDATE #EKGSummary
  SET Indication = ''
  WHERE Indication = @TestReason

  -- determine the person who read the ECG
  DECLARE @ReviewedBy varchar(30) = (SELECT
    MatchString
  FROM #QuantitativeMatch
  WHERE VariableName = 'EKG_Reader')

  UPDATE #EKGSummary
  SET Interpreter = StringValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE CHARINDEX(@ReviewedBy, Narrative) > 0

  -- determine the date of the evaluation
  UPDATE #EKGSummary
  SET InterpretationTime =
                          CASE
                            WHEN Interpreter LIKE '%/%/%:%' THEN CASE
                                WHEN ISDATE(REPLACE(SUBSTRING(Interpreter, CHARINDEX(')', Interpreter) + 5, 100), '"', '')) = 1 THEN REPLACE(SUBSTRING(Interpreter, CHARINDEX(')', Interpreter) + 5, 100), '"', '')
                                ELSE NULL
                              END
                            ELSE NULL
                          END

  -- fix the formatting of the prerson interpretting the study if there rare () around the name
  UPDATE #EKGSummary
  SET Interpreter =
                   CASE
                     WHEN CHARINDEX(')', Interpreter) > 0 THEN SUBSTRING(Interpreter, 1, CHARINDEX(')', Interpreter))
                     ELSE Interpreter
                   END

  UPDATE #EKGSummary
  SET QT = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'QT'
  UPDATE #EKGSummary
  SET QTc = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'QTc'
  UPDATE #EKGSummary
  SET QRS = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'QRS'
  UPDATE #EKGSummary
  SET PR = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'PR'
  UPDATE #EKGSummary
  SET V_Rate = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'V_Rate'
  UPDATE #EKGSummary
  SET A_Rate = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'A_Rate'
  UPDATE #EKGSummary
  SET P_Axis = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'P_Axis'
  UPDATE #EKGSummary
  SET R_Axis = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'R_Axis'
  UPDATE #EKGSummary
  SET T_Axis = NumericValue
  FROM #EKGSummary a
  INNER JOIN #EKG_Quantitative b
    ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
  WHERE VariableName = 'T_Axis'

  -- select * from #EKGSummary

  -- ***************************************************************
  -- * Process the ECG narratives to determine the diagnoses
  -- * During preprocessing, rows with lines without diagnostic information are marked with a 1
  -- * and rows with quantitative infomration are marked with a 2.
  -- * ignore both
  -- ***************************************************************


  -- **************************************************
  -- get the sql statements to be applied for diagnostic purposes
  -- **************************************************

  -- drop table #DiagnosisEvaluation
  CREATE TABLE #SQL (
    idx int IDENTITY (1, 1),
    sql nvarchar(max)
  )

  TRUNCATE TABLE #SQL
  INSERT INTO #SQL
    SELECT
      sql
    FROM dbo.ECG_DiagnosisMatch
    WHERE sql IS NOT NULL


  -- to look at the SQL statements, execute the next commented line
  -- SELECT * FROM #SQL

  TRUNCATE TABLE #DiagnosisEvaluation
  DECLARE @SQL3 nvarchar(max)
  DECLARE @j int = 1
  DECLARE @jMax int = (SELECT
    MAX(idx)
  FROM #SQL)

  WHILE @j <= @jMax
  BEGIN
    SET @SQL3 = (SELECT
      sql
    FROM #SQL
    WHERE idx = @j)
    EXEC (@SQL3)
    SET @j = @j + 1
  END


  -- determine if a diagnosis is noted as possible normal variant, or only possibly likely
  TRUNCATE TABLE #DiagnosisEvaluationHedged

  INSERT INTO #DiagnosisEvaluationHedged
    SELECT
      a.*,
      b.*,
      CHARINDEX(b.phrase, a.Narrative)
    FROM #DiagnosisEvaluation a,
         #HedgePhrases b
    WHERE CHARINDEX(b.phrase, a.Narrative) > 0

  -- mark the rows where the diagnosis is uncertain
  UPDATE #DiagnosisEvaluationHedged
  SET DiagnosisUncertain = 1
  WHERE HedgeLocation < MatchLocation	-- hedge word has to before the match on the line.

  -- 01/22/21 RHE also mark diagnoses as hedged if the narrative ends with the phrase. 
  -- The cardiologists sometimes tack the hedge word on at the end of the diagnosis line
  UPDATE #DiagnosisEvaluationHedged
  SET DiagnosisUncertain = 1
  FROM #DiagnosisEvaluationHedged a
  INNER JOIN (SELECT
    a.IDX,
    a.Diagnosis,
    DiagnosisUncertain
  FROM #DiagnosisEvaluation a,
       #HedgePhrases b
  WHERE Narrative LIKE '%' + phrase) x
    ON a.idx = x.idx
    AND a.diagnosis = x.diagnosis
  WHERE a.DiagnosisUncertain = 0

  UPDATE #DiagnosisEvaluation
  SET DiagnosisUncertain = b.DiagnosisUncertain
  FROM #DiagnosisEvaluation a
  INNER JOIN #DiagnosisEvaluationHedged b
    ON a.idx = b.idx
    AND a.Diagnosis = b.diagnosis
  WHERE b.DiagnosisUncertain = 1


  -- ********************************************
  -- Save the results of the analysis
  -- ********************************************

  -- results of ECG narrative interpretation
  TRUNCATE TABLE dbo.ECG_ResultsDiagnostic
  INSERT INTO dbo.ECG_ResultsDiagnostic
    SELECT DISTINCT
      PAT_ID,
      ORDER_PROC_ID,
      ECGDate,
      NarrativeRaw,
      Narrative,
      Code,
      Diagnosis,
      DiagnosisUncertain
    FROM #DiagnosisEvaluation
    WHERE Ignore = 0
    ORDER BY ECGDate, PAT_ID



  -- results of the quantitative analysis
  TRUNCATE TABLE dbo.ECG_ResultsQuantitative
  INSERT INTO dbo.ECG_ResultsQuantitative
    SELECT
      *
    FROM #EKGSummary
    WHERE Interpreter IS NOT NULL



  -- ************************************************************
  -- *  This is for the evaluation of a narrative datset being used for testing and modification of the configuration files
  -- *  It is executed conditionally based on  @EvaluatePerformance = 1
  -- ***********************************************************************

  --DECLARE @EvaluatePerformance tinyint = 1 -- 1= generate the output for analysis of the processing;  0=skip the analysis (for production use)

  IF @EvaluatePerformance = 1
  BEGIN

    -- drop table #Performance
    CREATE TABLE #Performance (
      idx int IDENTITY (1, 1),
      Narrative varchar(1024),
      code varchar(4),
      Diagnosis varchar(100),
      MatchLocation int,
      HedgeCode char(3),
      HedgePhrase varchar(100),
      HedgeLocation int,
      Ignore tinyint,
      MergedCode varchar(30)
    )
    TRUNCATE TABLE #Performance
    INSERT INTO #Performance
      SELECT
        Narrative,
        Code,
        Diagnosis,
        MatchLocation,
        HedgeCode,
        HedgePhrase,
        HedgeLocation,
        Ignore,
        Code
      FROM #DiagnosisEvaluationHedged
      UNION
      SELECT
        a.Narrative,
        a.Code,
        a.Diagnosis,
        a.MatchLocation,
        NULL AS HedgeCode,
        NULL AS HedgePhrase,
        NULL AS HedgeLocation,
        Ignore,
        Code AS MergedCode
      FROM #DiagnosisEvaluation a
      WHERE RTRIM(a.narrative) + RTRIM(a.diagnosis)
      NOT IN (SELECT
        RTRIM(narrative) + RTRIM(diagnosis)
      FROM #DiagnosisEvaluationHedged)
      ORDER BY narrative, diagnosis, hedgephrase


    UPDATE #Performance
    SET MergedCode = mergedCode +
    CASE
      WHEN HedgeCode IS NULL THEN ''
      ELSE '-' + HedgeCode
    END
    WHERE HedgeLocation < MatchLocation

    -- get rid of the hedge pharse where there is no merged code; this means that the hedge phrase occurred after the diagnosis, and thus does not apply
    UPDATE #Performance
    SET HedgePhrase = ''
    WHERE MergedCode NOT LIKE '%-%'
    AND hedgephrase NOT LIKE '%normal variant%'   --- 1/18/21 When normal variant appears, it is after the diagnosis, so don't exclude as per code in previous line

    -- drop table #UniqueNarratives
    CREATE TABLE #UniqueNarratives (
      idx int IDENTITY (1, 1),
      Narrative varchar(1024),
      Ignore tinyint
    )
    TRUNCATE TABLE #UniqueNarratives
    INSERT INTO #UniqueNarratives
      SELECT
        narrative,
        ignore
      FROM #Performance
      ORDER BY narrative

    -- ****************************************************
    -- * # of EKGs analyzed 
    -- ****************************************************
    SELECT
      COUNT(x.order_proc_id) AS [# ECG Processed]
    FROM (SELECT DISTINCT
      order_proc_id
    FROM #EKG) x

    -- *******************************************************
    -- * Full list of distinct lines and the diagnoses matched
    -- * For a full evaluation of performance, one will need to check the
    -- * accuracy of the matching for each line.
    -- * Narrative lines matching to >1 diagnosis will be displayed multiple times,
    -- * 1x for each diagnosis
    -- * Configuration tables may need to be adjusted to improve accuracy
    -- *******************************************************

    TRUNCATE TABLE dbo.ECG_PerformanceAllNarratives
    INSERT INTO dbo.ECG_PerformanceAllNarratives
      SELECT
        x.idx,
        x.narrative,
        x.code,
        x.Diagnosis,
        x.HedgePhrase,
        y.n AS n
      FROM (SELECT DISTINCT
        b.idx,
        a.narrative,
        a.Code,
        a.Diagnosis,
        ISNULL(HedgePhrase, '') AS HedgePhrase
      FROM #Performance a
      INNER JOIN #UniqueNarratives b
        ON a.Narrative = b.narrative
      WHERE a.ignore = 0
      --order by narrative, a.diagnosis, HedgePhrase
      ) x
      LEFT JOIN (SELECT
        narrative,
        COUNT(narrative) AS n
      FROM #EKG
      GROUP BY narrative) y
        ON x.narrative = y.narrative
      ORDER BY x.narrative, x.diagnosis, x.HedgePhrase

    -- For evaluation of the algoritm performance among all EKGs
    -- select * from dbo.ECG_PerformanceAllNarratives where code <> 927 order by narrativeID, code


    -- *****************************************************************
    -- * List the diagnosis matches for each distinct narrative
    -- * write the output to the table dbo.ECG_DiscretePerformance
    -- * Export to Excel for checking and possible modification of diagnosis matching
    -- *****************************************************************
    TRUNCATE TABLE dbo.ECG_PerformanceDiscreteNarratives
    INSERT INTO dbo.ECG_PerformanceDiscreteNarratives
      SELECT
        Narrative,
        Code,
        Diagnosis,
        HedgePhrase,
        SUM(n) AS n
      FROM dbo.ECG_PerformanceAllNarratives
      GROUP BY Narrative,
               Code,
               Diagnosis,
               HedgePhrase
      ORDER BY Narrative,
      Diagnosis,
      HedgePhrase

    -- For evaluation of the algorithm performance among distinct narratives
    -- select * from dbo.ECG_PerformanceDiscreteNarratives where narrative like '%.'
    -- select distinct narrative, code, diagnosis from dbo.ECG_PerformanceDiscreteNarratives where code<900  order by narrative, diagnosis

    -- *******************************************************
    -- * Distinct narrative lines that did not match any diagnosis
    -- * the counts of the the distinct lines are displayed
    -- * may need to adjust the configuration tables to classify lines without matches
    -- * suggest ignoring lines that are only represented once in the database
    -- * Lines with no diagnostoc information should be ignored
    -- *******************************************************
    TRUNCATE TABLE dbo.ECG_PerformanceNarrativesWithoutDiagnosis
    INSERT INTO dbo.ECG_PerformanceNarrativesWithoutDiagnosis
      SELECT
        a.Narrative,
        COUNT(a.narrative) AS n
      FROM #EKG a
      LEFT JOIN dbo.ECG_PerformanceAllNarratives b
        ON a.narrative = b.narrative
      WHERE a.Ignore = 0
      AND b.narrative IS NULL
      AND a.narrative <> ''
      GROUP BY a.narrative
      ORDER BY n DESC


    UPDATE dbo.ecg_narratives
    SET narrative = ''
    FROM dbo.ECG_Narratives a
    INNER JOIN (SELECT
      a.ORDER_PROC_ID
    --,a.NarrativeRaw
    --,a.Narrative
    FROM dbo.ECG_Narratives a
    INNER JOIN #EKG b
      ON a.ORDER_PROC_ID = b.ORDER_PROC_ID
    WHERE b.narrative = '') x
      ON a.ORDER_PROC_ID = x.ORDER_PROC_ID




    -- *************************************************************
    -- 	Results or evaluation of accuracy of matchinng of diagnoses
    -- *************************************************************
    SELECT
      'Results of matching all distinct narratives to diagnoses' AS 'Output Table'
    /*
    select	
    ORDER_PROC_ID,	
    NarrativeRaw,	
    Narrative,	
    Code,	
    Diagnosis,
    DiagnosisUncertain
    from dbo.ECG_ResultsDiagnostic 
    UNION
    select 
    a.ORDER_PROC_ID	,
    a.NarrativeRaw,	
    a.Narrative as Narrative	,
    null as Code,	
    null as Diagnosis,
    null as DiagnosisUncertain
    from dbo.ECG_Narratives a left join dbo.ECG_ResultsDiagnostic b
    on a.ORDER_PROC_ID = b.order_proc_id
    where b.ORDER_PROC_ID is null
    ORDER by code --ORDER_PROC_ID, Narrative, Code
    */

    SELECT
      Narrative,
      Code,
      Diagnosis,
      HedgePhrase,
      n
    FROM dbo.ECG_PerformanceDiscreteNarratives
    ORDER BY Narrative, Diagnosis


    -- *************************************************************
    -- 	Narratives not matching any diagnosis
    -- *************************************************************
    SELECT
      'Narratives without a diagnostic match' AS 'Output Table'
    SELECT
      Narrative,
      n
    FROM dbo.ECG_PerformanceNarrativesWithoutDiagnosis


    -- *************************************************************
    -- 	Results of the quantitative matching
    -- *************************************************************
    SELECT
      'Results of the quantitative matching' AS 'Output Table'
    SELECT
      *
    FROM dbo.ECG_ResultsQuantitative


  END


  IF OBJECT_ID('tempdb.dbo.#DiagnosisExclusions') IS NOT NULL
    DROP TABLE #DiagnosisExclusions
  IF OBJECT_ID('tempdb.dbo.#HedgePhrases') IS NOT NULL
    DROP TABLE #HedgePhrases
  IF OBJECT_ID('tempdb.dbo.#QuantitativeMatch') IS NOT NULL
    DROP TABLE #QuantitativeMatch
  IF OBJECT_ID('tempdb.dbo.#MatchTypeExclusion') IS NOT NULL
    DROP TABLE #MatchTypeExclusion
  IF OBJECT_ID('tempdb.dbo.#EKG') IS NOT NULL
    DROP TABLE #EKG
  IF OBJECT_ID('tempdb.dbo.#ECG_DiagnosesNoLongerPresent') IS NOT NULL
    DROP TABLE #ECG_DiagnosesNoLongerPresent
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluation') IS NOT NULL
    DROP TABLE #DiagnosisEvaluation
  IF OBJECT_ID('tempdb.dbo.#EKG_Quantitative') IS NOT NULL
    DROP TABLE #EKG_Quantitative
  IF OBJECT_ID('tempdb.dbo.#EKGSummary') IS NOT NULL
    DROP TABLE #EKGSummary
  IF OBJECT_ID('tempdb.dbo.#SQL') IS NOT NULL
    DROP TABLE #SQL
  IF OBJECT_ID('tempdb.dbo.#DiagnosisEvaluationHedged') IS NOT NULL
    DROP TABLE #DiagnosisEvaluationHedged
  IF OBJECT_ID('tempdb.dbo.#Performance') IS NOT NULL
    DROP TABLE #Performance
  IF OBJECT_ID('tempdb.dbo.#UniqueNarratives') IS NOT NULL
    DROP TABLE #UniqueNarratives

GO

/****** Object:  StoredProcedure [dbo].[Epic_Find_PROC_ID_ECGinLabs]    Script Date: 6/25/2021 12:46:34 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
/* 
dbo.Epic_Find_PROC_ID_ECGinLabs

Copyringt (C) 2021
Author: Ricahrd H. Epstein, MD

Determine the locations of the ECG diagnosis results for Epic implementations where these are stored as labs
rather than narratives



Change Control
Date  	Ver		By		Note
02/08/21	1.00	RHE		Initial coding for VUMC 


*/

--/*
CREATE PROC [dbo].[Epic_Find_PROC_ID_ECGinLabs]
AS
  --*/



  -- *****************************************************************************
  -- Step 1. This will list all the PROC_ID potentially related to an EKG
  -- Note the PROC_ID's that are related to a 12-lead EKG for the next section
  -- ******************************************************************************
  SELECT
    PROC_ID,
    Description,
    COUNT(proc_id) AS n
  FROM clarity.dbo.order_proc WITH (NOLOCK)
  WHERE Description LIKE '%e[ck]g%'
  GROUP BY PROC_ID,
           DESCRIPTION
  ORDER BY n DESC


  -- *****************************************************************************
  -- Step 2. Get the component ID's associated with the PROC_ID related to 12 lead ECG impressions
  -- where the results are in the lab table
  -- Replace the value of the PROC_ID with the value from your system
  -- For example, at VUMC the component names will be ECG Impresion and ECG Severity T
  -- Note the component ID
  -- *****************************************************************************
  SELECT DISTINCT
    a.proc_ID,
    b.COMPONENT_ID,
    c.External_Name
  FROM clarity.dbo.ORDER_PROC a WITH (NOLOCK)
  INNER JOIN clarity.dbo.ORDER_RESULTS b WITH (NOLOCK)
    ON a.order_proc_id = b.order_proc_id
  INNER JOIN clarity.dbo.CLARITY_COMPONENT c
    ON b.COMPONENT_ID = c.COMPONENT_ID
  WHERE a.PROC_ID IN (509, 21000000009)
  AND c.external_name LIKE '%e[ck]g%'

  -- *****************************************************************************
  -- Step 3. get the distinct narrative results to evaluate for ECG NLP config table changes
  -- Substitute the values of the PROC_IDs and the COMPONENT_IDs that have the 
  -- ECG Severity T and ECG Impression components
  -- this will pull all the distinct narratives from 1/1/2019
  -- ******************************************************************************
  SELECT
    ORD_VALUE AS Narrative,
    COUNT(ord_VALUE) AS n
  FROM clarity.dbo.ORDER_PROC a WITH (NOLOCK)
  INNER JOIN clarity.dbo.ORDER_RESULTS b
    ON a.order_proc_id = b.order_proc_id
  WHERE PROC_ID IN (174895)
  AND COMPONENT_ID IN (11603, 11628)
  AND ORDER_INST > '2019-01-01'
  GROUP BY ord_value
  ORDER BY n DESC


GO




-- Now run the stored procedures to create the tables and populate them
SELECT 'Creating and loading the ECG NLP tables' as Message
EXEC [dbo].[ECG_CreateTablesForNLProcessing]


-- load the sample narratives text file
SELECT 'Loading the sample ECG narrative file' as Message
EXEC [dbo].[ECG_LoadNarratives_Text]

-- run the analysis of the sample narrative file
SELECT 'Analyzing the ECG narrative file' as Message
EXEC dbo.ECG_PreprocessNarratives
EXEC dbo.ECG_ProcessNarratives 1


-- *************************************************************
-- 	Results of the matching for the sample ECG narratives file
-- *************************************************************
SELECT
  'Diagnostic matches for the sample ECG narratives file' AS 'Output Table'
SELECT
  *
FROM dbo.ECG_ResultsDiagnostic

SELECT
  'Quantitative matches for the sample ECG narratives file' AS 'Output Table'
SELECT
  *
FROM dbo.ECG_ResultsQuantitative