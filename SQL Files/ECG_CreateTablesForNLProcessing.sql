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


